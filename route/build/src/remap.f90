module remapping

  ! data types
  use nrtype
  use dataTypes, only : remap                ! remapping data type
  use dataTypes, only : runoff               ! runoff data type
  use dataTypes, only : var_ilength          ! integer type:          var(:)%dat
  use dataTypes, only : var_dlength          ! double precision type: var(:)%dat

  ! parameter structures
  USE dataTypes,  only : RCHPRP              ! Reach parameters (properties)
  USE dataTypes,  only : RCHTOPO             ! Network topology

  ! look-up variables
  use var_lookup,only:ixHRU,    nVarsHRU     ! index of variables for the HRUs
  use var_lookup,only:ixSEG,    nVarsSEG     ! index of variables for the stream segments
  use var_lookup,only:ixHRU2SEG,nVarsHRU2SEG ! index of variables for the hru2segment mapping
  use var_lookup,only:ixNTOPO,  nVarsNTOPO   ! index of variables for the network topology

  ! global data
  USE public_var,only:runoffMin, negRunoffTol, integerMissing
  USE globalData,only:time_conv,length_conv  ! conversion factors

  implicit none
  private
  public ::remap_runoff
  public ::basin2reach

  contains

  ! *****
  ! * public subroutine: used to map runoff data (on diferent grids/polygons) to the basins in the routing layer...
  ! ***************************************************************************************************************
  subroutine remap_runoff(runoff_data_in, remap_data_in, basinRunoff, ierr, message)
  implicit none
  ! input
  type(runoff)         , intent(in)  :: runoff_data_in   ! runoff for one time step for all HRUs
  type(remap)          , intent(in)  :: remap_data_in    ! data structure to remap data from a polygon (e.g., grid) to another polygon (e.g., basin)
  ! output
  real(dp)             , intent(out) :: basinRunoff(:)   ! basin runoff
  integer(i4b)         , intent(out) :: ierr             ! error code
  character(len=strLen), intent(out) :: message          ! error message
  ! local
  character(len=strLen)              :: cmessage         ! error message from subroutine

  ierr=0; message="remap_runoff/"

  if (runoff_data_in%nSpace(2) == integerMissing) then
    call remap_1D_runoff(runoff_data_in, remap_data_in, basinRunoff, ierr, cmessage)
    if(ierr/=0)then; message=trim(message)//trim(cmessage); return; endif
  else
    call remap_2D_runoff(runoff_data_in, remap_data_in, basinRunoff, ierr, cmessage)
    if(ierr/=0)then; message=trim(message)//trim(cmessage); return; endif
  endif

  end subroutine remap_runoff

  ! *****
  ! private subroutine: used to map runoff data (on diferent polygons) to the basins in the routing layer...
  ! ***************************************************************************************************************
  subroutine remap_2D_runoff(runoff_data_in, remap_data_in, basinRunoff, ierr, message)
  implicit none
  ! input
  type(runoff)         , intent(in)  :: runoff_data_in      ! runoff for one time step for all HRUs
  type(remap)          , intent(in)  :: remap_data_in       ! data structure to remap data from a polygon (e.g., grid) to another polygon (e.g., basin)
  ! output
  real(dp)             , intent(out) :: basinRunoff(:)      ! basin runoff
  integer(i4b)         , intent(out) :: ierr                ! error code
  character(len=strLen), intent(out) :: message             ! error message
  ! local
  integer(i4b)                       :: iHRU,jHRU           ! index of basin in the routing layer
  integer(i4b)                       :: ixOverlap           ! index in ragged array of overlapping polygons
  integer(i4b)                       :: ii,jj               ! index of x and y in grid
  integer(i4b)                       :: ixPoly              ! loop through overlapping polygons for a given basin
  real(dp)                           :: sumWeights          ! used to check that the sum of weights equals one
  real(dp)    , parameter            :: xTol=1.e-6_dp       ! tolerance to avoid divide by zero
  integer(i4b), parameter            :: ixCheck=-huge(iHRU) ! basin to check
  integer(i4b), parameter            :: jxCheck=-huge(iHRU) ! basin to check
  logical(lgt), parameter            :: printWarn=.false.   ! flag to print warnings
  ierr=0; message="remap_2D_runoff/"

  ! initialize counter for the overlap vector
  ixOverlap = 1

  ! loop through hrus in the mapping layer
  do iHRU=1,size(remap_data_in%hru_ix)

   ! define the HRU index in the routing vector
   jHRU = remap_data_in%hru_ix(iHRU)

   ! if mapping data has hrus that do not exist in river network, skip that hru
   ! but increment index of weight and overlap-poly-id arrays
   if (jHRU == integerMissing)then
    if (remap_data_in%num_qhru(iHRU)/=integerMissing)then
      ixOverlap = ixOverlap + remap_data_in%num_qhru(iHRU)
    endif
    cycle
   endif

   ! initialize the weighted average
   sumWeights        = 0._dp
   basinRunoff(jHRU) = 0._dp

   ! loop through the overlapping polygons
   do ixPoly=1,remap_data_in%num_qhru(iHRU) ! number of overlapping polygons

    ! index of i (x) and j (y) direction
    jj = remap_data_in%j_index(ixOverlap)
    ii = remap_data_in%i_index(ixOverlap)

    ! check i-indices
    if(ii < lbound(runoff_data_in%qSim2d,1) .or. ii > ubound(runoff_data_in%qSim2d,1))then
     if(printWarn) write(*,'(a,4(i0,a))') trim(message)//'WARNING: When computing weighted runoff at ', jHRU, 'th-HRU, i-index ', ii,' was not found in runoff grid data.'
     ixOverlap = ixOverlap + 1; cycle
    endif

    ! check j-indices
    if(jj < lbound(runoff_data_in%qSim2d,2) .or. jj > ubound(runoff_data_in%qSim2d,2))then
     if(printWarn) write(*,'(a,4(i0,a))') trim(message)//'WARNING: When computing weighted runoff at ', jHRU, 'th-HRU, j-index ', jj, 'was not found in runoff grid data.'
     ixOverlap = ixOverlap + 1; cycle
    endif

    ! get the weighted average
    if(runoff_data_in%qSim2d(ii,jj) > -xTol)then
     sumWeights        = sumWeights        + remap_data_in%weight(ixOverlap)
     basinRunoff(jHRU) = basinRunoff(jHRU) + remap_data_in%weight(ixOverlap)*runoff_data_in%qSim2D(ii,jj)
    endif

    ! check
    if(remap_data_in%i_index(iHRU)==ixCheck .and. remap_data_in%j_index(iHRU)==jxCheck)then
     print*, 'remap_data_in%i_index(iHRU),remap_data_in%j_index(iHRU) = ', remap_data_in%i_index(iHRU), remap_data_in%j_index(iHRU)
     print*, 'remap_data_in%num_qhru(iHRU)                            = ', remap_data_in%num_qhru(iHRU)
     print*, 'runoff_data_in%qSim2D(ii,jj)                            = ', runoff_data_in%qSim2D(ii,jj)
    endif

    ! increment the overlap index
    ixOverlap = ixOverlap + 1

   end do  ! looping through overlapping polygons

   ! compute weighted average
   if(sumWeights>xTol)then
    if(abs(1._dp - sumWeights)>xTol) basinRunoff(jHRU) = basinRunoff(jHRU) / sumWeights
   endif

   ! check
   if(remap_data_in%i_index(iHRU)==ixCheck .and. remap_data_in%j_index(iHRU)==jxCheck)then
    print*, 'basinRunoff(jHRU) = ', basinRunoff(jHRU)*86400._dp*1000._dp*365._dp
    print*, 'PAUSE : '; read(*,*)
   endif

   ! print progress
   !if(mod(iHRU,100000)==0)then
   ! print*, trim(message)//'mapping runoff, iHRU, basinRunoff(jHRU) = ', &
   !                                         iHRU, basinRunoff(jHRU)
   !endif

  end do   ! looping through basins in the mapping layer

  !!print*, 'PAUSE: after remap_2D_runoff'; read(*,*)

  end subroutine remap_2D_runoff

  ! *****
  ! private subroutine: used to map runoff data (on diferent polygons) to the basins in the routing layer...
  ! ***************************************************************************************************************
  subroutine remap_1D_runoff(runoff_data_in, remap_data_in, basinRunoff, ierr, message)
  implicit none
  ! input
  type(runoff)         , intent(in)  :: runoff_data_in   ! runoff for one time step for all HRUs
  type(remap)          , intent(in)  :: remap_data_in    ! data structure to remap data from a polygon (e.g., grid) to another polygon (e.g., basin)
  ! output
  real(dp)             , intent(out) :: basinRunoff(:)   ! basin runoff
  integer(i4b)         , intent(out) :: ierr             ! error code
  character(len=strLen), intent(out) :: message          ! error message
  ! local
  integer(i4b)                       :: iHRU,jHRU        ! index of basin in the routing layer
  integer(i4b)                       :: ixOverlap        ! index in ragged array of overlapping polygons
  integer(i4b)                       :: ixRunoff         ! index in the runoff vector
  integer(i4b)                       :: ixPoly           ! loop through overlapping polygons for a given basin
  real(dp)                           :: sumWeights       ! used to check that the sum of weights equals one
  real(dp)    , parameter            :: xTol=1.e-6_dp    ! tolerance to avoid divide by zero
  integer(i4b), parameter            :: ixCheck=-huge(iHRU) ! basin to check
  !integer(i4b), parameter            :: ixCheck=24001479 ! basin to check

  ierr=0; message="remap_1D_runoff/"

  ! initialize counter for the overlap vector
  ixOverlap = 1

  ! loop through hrus in the mapping layer
  do iHRU=1,size(remap_data_in%hru_ix)

   ! define the HRU index in the routing vector
   jHRU = remap_data_in%hru_ix(iHRU)

   ! if mapping data has hrus that do not exist in river network, skip that hru
   ! but increment index of weight and overlap-poly-id arrays
   if (jHRU == integerMissing)then
    if (remap_data_in%num_qhru(iHRU)/=integerMissing)then
      ixOverlap = ixOverlap + remap_data_in%num_qhru(iHRU)
    endif
    cycle
   endif

   !print*, 'remap_data_in%hru_id(iHRU), remap_data_in%num_qhru(iHRU) = ', &
   !         remap_data_in%hru_id(iHRU), remap_data_in%num_qhru(iHRU)

   ! initialize the weighted average
   sumWeights        = 0._dp
   basinRunoff(jHRU) = 0._dp

   ! loop through the overlapping polygons
   do ixPoly=1,remap_data_in%num_qhru(iHRU) ! number of overlapping polygons

    ! check that the cell exists in the runoff file
    !print*, 'ixOverlap, remap_data_in%qhru_ix(ixOverlap) = ', ixOverlap, remap_data_in%qhru_ix(ixOverlap)
    if(remap_data_in%qhru_ix(ixOverlap)==integerMissing)then
     ixOverlap = ixOverlap + 1
     cycle
    endif

    ! get the index in the runoff file
    ixRunoff = remap_data_in%qhru_ix(ixOverlap)

    ! check that we have idenbtified the correct runoff HRU
    if( remap_data_in%qhru_id(ixOverlap) /= runoff_data_in%hru_id(ixRunoff) )then
     message=trim(message)//'mismatch in HRU ids for polygons in the runoff layer'
     ierr=20; return
    endif

    ! get the weighted average
    if(runoff_data_in%qSim(ixRunoff) > -xTol)then
     sumWeights        = sumWeights        + remap_data_in%weight(ixOverlap)
     basinRunoff(jHRU) = basinRunoff(jHRU) + remap_data_in%weight(ixOverlap)*runoff_data_in%qSim(ixRunoff)
    endif

    ! check
    if(remap_data_in%hru_id(iHRU)==ixCheck)then
     print*, 'remap_data_in%hru_id(iHRU)                         = ', remap_data_in%hru_id(iHRU)
     print*, 'remap_data_in%num_qhru(iHRU)                       = ', remap_data_in%num_qhru(iHRU)
     print*, 'ixRunoff, runoff_data_in%qSim(ixRunoff)            = ', ixRunoff, runoff_data_in%qSim(ixRunoff)
    endif

    !print*, 'remap_data_in%qhru_id(ixOverlap), runoff_data_in%hru_id(ixRunoff), remap_data_in%weight(ixOverlap), runoff_data_in%qSim(ixRunoff) = ', &
    !         remap_data_in%qhru_id(ixOverlap), runoff_data_in%hru_id(ixRunoff), remap_data_in%weight(ixOverlap), runoff_data_in%qSim(ixRunoff)

    ! increment the overlap index
    ixOverlap = ixOverlap + 1

   end do  ! looping through overlapping polygons

   ! compute weighted average
   if(sumWeights>xTol)then
    if(abs(1._dp - sumWeights)>xTol) basinRunoff(jHRU) = basinRunoff(jHRU) / sumWeights
   endif

   ! check
   if(remap_data_in%hru_id(iHRU)==ixCheck)then
    print*, 'basinRunoff(jHRU) = ', basinRunoff(jHRU)*86400._dp*1000._dp*365._dp
    print*, 'PAUSE : '; read(*,*)
   endif

   ! print progress
   !if(mod(iHRU,100000)==0)then
   ! print*, trim(message)//'mapping runoff, iHRU, basinRunoff(jHRU) = ', &
   !                                         iHRU, basinRunoff(jHRU)
   !endif

   !print*, 'basinRunoff(jHRU) = ', basinRunoff(jHRU)
   !print*, 'PAUSE : '; read(*,*)

  end do   ! looping through basins in the mapping layer

  end subroutine remap_1D_runoff

  ! *****
  ! * public subroutine: used to obtain streamflow for each stream segment...
  ! *************************************************************************
  subroutine basin2reach(&
                         ! input
                         basinRunoff,       & ! basin runoff (m/s)
                         NETOPO_in,         & ! reach topology data structure
                         RPARAM_in,         & ! reach parameter data structure
                         ! output
                         reachRunoff,       & ! intent(out): reach runoff (m/s)
                         ierr, message)       ! intent(out): error control

  implicit none
  ! input
  real(dp)                  , intent(in)  :: basinRunoff(:)   ! basin runoff (m/s)
  type(RCHTOPO), allocatable, intent(in)  :: NETOPO_in(:)     ! River Network topology
  type(RCHPRP),  allocatable, intent(in)  :: RPARAM_in(:)     ! River (non-)physical parameters
  ! output
  real(dp)                  , intent(out) :: reachRunoff(:)   ! reach runoff (m/s)
  integer(i4b)              , intent(out) :: ierr             ! error code
  character(len=strLen)     , intent(out) :: message          ! error message
  ! ----------------------------------------------------------------------------------------------
  ! local
  integer(i4b)                            :: nContrib         ! number of contributing HRUs
  integer(i4b)                            :: iHRU             ! array index for contributing HRU
  integer(i4b)                            :: iSeg             ! array index for stream segment
  ! initialize error control
  ierr=0; message='basin2reach/'

  ! interpolate the data to the basins
  do iSeg=1,size(NETOPO_in)

   ! associate variables in data structure
   nContrib       = size(NETOPO_in(iSeg)%HRUID)
   associate(hruContribId   => NETOPO_in(iSeg)%HRUID,   & ! unique ids of contributing HRU
             hruContribIx   => NETOPO_in(iSeg)%HRUIX,   & ! index of contributing HRU
             basArea        => RPARAM_in(iSeg)%BASAREA, & ! basin (total contributing HRU) area
             hruWeight      => NETOPO_in(iSeg)%HRUWGT   ) ! weight assigned to each HRU

   ! * case where HRUs drain into the segment
   if(nContrib > 0)then

    ! intialize the streamflow
    reachRunoff(iSeg) = 0._dp

    ! loop through the HRUs
    do iHRU=1,nContrib

     ! error check - runoff depth cannot be negative (no missing value)
     if( basinRunoff( hruContribIx(iHRU) ) < negRunoffTol )then
      write(message,'(a,i0)') trim(message)//'exceeded negative runoff tolerance for HRU ', hruContribId(iHRU)
      ierr=20; return
     endif

     ! compute the weighted average runoff depth (m/s)
     reachRunoff(iSeg) = reachRunoff(iSeg) + hruWeight(iHRU)*basinRunoff( hruContribIx(iHRU) )*time_conv*length_conv

    end do  ! (looping through contributing HRUs)

    ! ensure that routed streamflow is non-zero
    if(reachRunoff(iSeg) < runoffMin) reachRunoff(iSeg) = runoffMin

    ! convert basin average runoff volume (m3/s)
    reachRunoff(iSeg) = reachRunoff(iSeg)*basArea

   ! * special case where no HRUs drain into the segment
   else
    reachRunoff(iSeg) = runoffMin
   endif

   ! end association to data structures
   end associate

  end do  ! looping through stream segments

  end subroutine basin2reach

!   ! *****
!   ! * public subroutine: used to obtain streamflow for each stream segment...
!   ! *************************************************************************
!   subroutine basin2reach_old(&
!                          ! input
!                          basinRunoff,       & ! intent(in):  basin runoff (m/s)
!                          structNTOPO,       & ! intent(in):  Network topology structure
!                          structSEG,         & ! intent(in):  Network attributes structure
!                          ! output
!                          reachRunoff,       & ! intent(out): reach runoff (m/s)
!                          ierr, message)       ! intent(out): error control
!   implicit none
!   ! input
!   real(dp)             , intent(in)  :: basinRunoff(:)   ! basin runoff (m/s)
!   type(var_ilength)    , intent(in)  :: structNTOPO(:)   ! Network topology structure
!   type(var_dlength)    , intent(in)  :: structSEG(:)     ! Network attributes structure
!   ! output
!   real(dp)             , intent(out) :: reachRunoff(:)   ! reach runoff (m/s)
!   integer(i4b)         , intent(out) :: ierr             ! error code
!   character(len=strLen), intent(out) :: message          ! error message
!   ! ----------------------------------------------------------------------------------------------
!   ! local
!   integer(i4b)                       :: iHRU             ! array index for contributing HRU
!   integer(i4b)                       :: iSeg             ! array index for stream segment
!   ! initialize error control
!   ierr=0; message='basin2reach_old/'
!
!   ! interpolate the data to the basins
!   do iSeg=1,size(structSEG)
!
!    ! associate variables in data structure
!    associate(nContrib       => structNTOPO(iSeg)%var(ixNTOPO%nHRU)%dat(1),      & ! contributing HRUs
!              hruContribIx   => structNTOPO(iSeg)%var(ixNTOPO%hruContribIx)%dat, & ! index of contributing HRU
!              hruContribId   => structNTOPO(iSeg)%var(ixNTOPO%hruContribId)%dat, & ! unique ids of contributing HRU
!              basArea        => structSEG(  iSeg)%var(ixSEG%basArea)%dat(1),     & ! basin (total contributing HRU) area
!              hruWeight      => structSEG(  iSeg)%var(ixSEG%weight)%dat          ) ! weight assigned to each HRU
!
!    ! * case where HRUs drain into the segment
!    if(nContrib > 0)then
!
!     ! intialize the streamflow
!     reachRunoff(iSeg) = 0._dp
!
!     ! loop through the HRUs
!     do iHRU=1,nContrib
!
!      ! error check - runoff depth cannot be negative (no missing value)
!      if( basinRunoff( hruContribIx(iHRU) ) < negRunoffTol )then
!       write(message,'(a,i0)') trim(message)//'exceeded negative runoff tolerance for HRU ', hruContribId(iHRU)
!       ierr=20; return
!      endif
!
!      ! compute the weighted average runoff depth (m/s)
!      reachRunoff(iSeg) = reachRunoff(iSeg) + hruWeight(iHRU)*basinRunoff( hruContribIx(iHRU) )*time_conv*length_conv
!
!     end do  ! (looping through contributing HRUs)
!
!     ! ensure that routed streamflow is non-zero
!     if(reachRunoff(iSeg) < runoffMin) reachRunoff(iSeg) = runoffMin
!
!     ! convert basin average runoff volume (m3/s)
!     reachRunoff(iSeg) = reachRunoff(iSeg)*basArea
!
!    ! * special case where no HRUs drain into the segment
!    else
!     reachRunoff(iSeg) = runoffMin
!    endif
!
!    ! end association to data structures
!    end associate
!
!   end do  ! looping through stream segments
!
!   end subroutine basin2reach_old

end module remapping
