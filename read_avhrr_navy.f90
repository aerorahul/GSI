subroutine read_avhrr_navy(mype,val_avhrr,ithin,rmesh,jsatid,&
     gstime,infile,lunout,obstype,nread,ndata,nodata,twind,sis, &
     mype_root,mype_sub,npe_sub,mpi_comm_sub)
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    read_avhrr_navy                  read navy avhrr data
!   prgmmr: li, xu           org: np23                date: 2003-03-26
!
! abstract:  This routine reads BUFR format AVHRR radiance (brightness
!            temperature) files from the U.S. Navy.  Optionally, the 
!            data are thinned to a specified resolution using simple 
!            quality control checks.
!
!            When running the gsi in regional mode, the code only
!            retains those observations that fall within the regional
!            domain
!
! program history log:
!   2003-03-26 li, xu  - read Navy avhrr_sst data
!   2004-05-28 kleist  - update subroutine call
!   2004-06-16 treadon - update documentation
!   2004-07-23 derber  - make changes to eliminate obs. earlier in thinning
!   2004-07-29 treadon - add only to module use, add intent in/out
!   2005-01-26 derber  - land/sea determination and weighting for data selection
!   2005-04-18 treadon - read in and interpolate hi-res SST analysis to obs locations
!   2005-09-08  derber - modify to use input group time window
!   2005-09-28  derber - modify to produce consistent surface info
!   2005-10-17  treadon - add grid and earth relative obs location to output file
!   2005-10-18  treadon - remove array obs_load and call to sumload
!   2005-10-19  li, xu  - modify to use new (operational bufr table)
!   2005-11-29  parrish - modify getsfc to work for different regional options
!   2006-02-01  parrish - remove getsfc (different version called now in read_obs)
!   2006-02-03  derber  - modify for new obs control and obs count
!   2006-04-21  keyser/treadon - add logic to correctly set BUFR subset
!   2006-04-27  derber - clean up code
!   2006-05-19  eliu    - add logic to reset relative weight when all channels not used
!   2006-07-28  derber  - add solar and satellite azimuth angles remove isflg from output
!   2007-03-01  tremolet - measure time from beginning of assimilation window
!   2008-05-28  safford - rm unused vars and uses
!   2008-10-10  derber  - modify to allow mpi_io
!   2008-12-30  todling - memory leak fix (data_crit,idata_itx)
!
!   input argument list:
!     mype     - mpi task id
!     val_avhrr- weighting factor applied to super obs
!     ithin    - flag to thin data
!     rmesh    - thinning mesh size (km)
!     jsatid   - satellite to read
!     gstime   - analysis time in minutes from reference date
!     infile   - unit from which to read BUFR data
!     lunout   - unit to which to write data for further processing
!     obstype  - observation type to process
!     twind    - input group time window (hours)
!     sis      - satellite/instrument/sensor indicator
!
!   output argument list:
!     nread    - number of BUFR NAVY AVHRR observations read
!     ndata    - number of BUFR NAVY AVHRR profiles retained for further processing
!     nodata   - number of BUFR NAVY AVHRR observations retained for further processing
!
! attributes:
!   language: f90
!   machine:  ibm RS/6000 SP
!
!$$$
  use kinds, only: r_kind,r_double,r_single,i_kind
  use satthin, only: super_val,itxmax,makegrids,map2tgrid,destroygrids, &
           finalcheck,score_crit
  use gridmod, only: diagnostic_reg,regional,nlat,nlon,tll2xy,txy2ll,rlats,rlons
  use constants, only: deg2rad, zero, one, rad2deg
  use radinfo, only: retrieval,iuse_rad,jpch_rad,nusis
  use gsi_4dvar, only: l4dvar, idmodel, iwinbgn, winlen
  implicit none


! Declare passed variables
  character(len=*),intent(in):: infile,obstype,jsatid
  character(len=*),intent(in):: sis
  integer(i_kind),intent(in):: mype,lunout,ithin
  integer(i_kind),intent(inout):: nread
  integer(i_kind),intent(inout):: ndata,nodata
  real(r_kind),intent(in):: rmesh,gstime,twind
  real(r_kind),intent(inout):: val_avhrr
  integer(i_kind),intent(in) :: mype_root
  integer(i_kind),intent(in) :: mype_sub
  integer(i_kind),intent(in) :: npe_sub
  integer(i_kind),intent(in) :: mpi_comm_sub


! Declare local parameters
  character(6),parameter:: file_sst='SST_AN'
  integer(i_kind),parameter:: maxinfo = 35
  integer(i_kind),parameter:: mlat_sst = 3000
  integer(i_kind),parameter:: mlon_sst = 5000
  real(r_kind),parameter:: r6=6.0_r_kind
  real(r_kind),parameter:: r60=60.0_r_kind
  real(r_kind),parameter:: r360=360.0_r_kind
  real(r_kind),parameter:: tbmin=50.0_r_kind
  real(r_kind),parameter:: tbmax=550.0_r_kind

  real(r_kind),parameter:: bmiss = 1.0E11


! Declare local variables  
  logical outside,iuse,assim
  character(1):: cdummy
  character(8):: subset

  integer(i_kind) klon1,klatp1,klonp1,klat1
  integer(i_kind) lnbufr,nchanl,iret
  integer(i_kind) idate,n
  integer(i_kind) ilat,ilon,iskip
  integer(i_kind) idummy1,idummy2,lun
  integer(i_kind),dimension(5):: idate5
  integer(i_kind) nmind,isc,isflg,idomsfc
  integer(i_kind) itx,k,i,bufsat,iout
  integer(i_kind) ireadsb,ireadmg
  integer(i_kind) nele,itt
  integer(i_kind) nlat_sst,nlon_sst

  real(r_kind) dlon,dlat,timedif,sfcr
  real(r_kind) dlon_earth,dlat_earth
  real(r_kind) w00,w01,w10,w11,dx1,dy1
  real(r_kind) pred,crit1,tdiff,sstime,dx,dy,dist1
  real(r_kind) dlat_sst,dlon_sst,sst_hires
  real(r_kind) :: tsavg,vty,vfr,sty,stp,sm,sn,zz,ff10
  real(r_kind) :: t4dv

  real(r_kind),dimension(0:4):: rlndsea
  real(r_kind),dimension(0:3):: sfcpct
  real(r_kind),dimension(0:3):: ts

  real(r_kind),dimension(mlat_sst):: rlats_sst
  real(r_kind),dimension(mlon_sst):: rlons_sst
  real(r_kind),dimension(mlat_sst,mlon_sst):: sst_an
  real(r_kind),allocatable,dimension(:,:):: data_all

  real(r_double),dimension(100):: bufrf                 ! array to store the read bufr record

  real(r_kind) disterr,disterrmax,dlon00,dlat00
  integer(i_kind) ntest


!**************************************************************************
! Start routine here.  Set constants.  Initialize variables
  disterrmax=zero
  lnbufr = 10
  ntest=0
  ndata  = 0
  nodata  = 0
  nchanl = 3

  ilon=3
  ilat=4

  rlndsea(0) = 0._r_kind
  rlndsea(1) = 30._r_kind
  rlndsea(2) = 20._r_kind
  rlndsea(3) = 30._r_kind
  rlndsea(4) = 30._r_kind

                            ! 207, 208 or 209 for NOAA-16, 17 & 18 respectively
  if(jsatid == 'n16')bufsat = 207
  if(jsatid == 'n17')bufsat = 208
  if(jsatid == 'n18')bufsat = 209
  if(jsatid == 'n19')bufsat = 223
  if(jsatid == 'metop-a')bufsat = 4

! If all channels of a given sensor are set to monitor or not
! assimilate mode (iuse_rad<1), reset relative weight to zero.
! We do not want such observations affecting the relative
! weighting between observations within a given thinning group.

  assim=.false.
  search: do i=1,jpch_rad
     if ((nusis(i)==sis) .and. (iuse_rad(i)>0)) then
        assim=.true.
        exit search
     endif
  end do search
  if (.not.assim) val_avhrr=zero


! Make thinning grids
  call makegrids(rmesh)


! Read hi-res sst analysis
  if (retrieval) call rdgrbsst(file_sst,mlat_sst,mlon_sst,&
       sst_an,rlats_sst,rlons_sst,nlat_sst,nlon_sst)


! Allocate arrays to hold all data for given satellite
  nele=maxinfo+nchanl
  allocate(data_all(nele,itxmax))

  open(lnbufr,file=infile,form='unformatted')         ! open bufr data file

! Associate the tables file with the message file, and identify th elatter to BUFRLIB software
  call openbf (lnbufr,'IN',lnbufr)

! Check to see if data are in message type NC012015 or in NC012012
! (should be in latter after spring 2006, will know this if
!  message typoe NC012015 is no longer present in BUFRLIB)

  subset = 'NC012012'
  call status(lnbufr,lun,idummy1,idummy2)
  call nemtab(lun,'NC012015',idummy1,cdummy,iret)
  if(iret.gt.0)  subset = 'NC012015'


! Read BUFR Navy data
  do while (ireadmg(lnbufr,subset,idate) == 0)

     read_loop:do while (ireadsb(lnbufr) == 0)
  
       call ufbint(lnbufr,bufrf(1),9,1,iret, &
       &            'YEAR MNTH DAYS HOUR MINU SECO CLAT CLON SAID')

        if ( bufsat /= nint(bufrf(9)) ) cycle read_loop               ! read next bufr subset
        call ufbint(lnbufr,bufrf(10),4,1,iret,'SAZA SOZA SOLAZI SSTYPE')
        call ufbint(lnbufr,bufrf(14),1,1,iret,'SST1')
        call ufbrep(lnbufr,bufrf(15),1,5,iret,'TMBR')

        iskip = 0
        do k=1,nchanl
           if(bufrf(16+k) < tbmin .or. bufrf(16+k) > tbmax) then
              iskip=iskip+1
           else
              nread=nread+1
           end if
        end do
        if(iskip >= nchanl)cycle read_loop

!       Extract date information.  If time outside window, skip this obs
        idate5(1) = nint(bufrf(1))    !year
        idate5(2) = nint(bufrf(2))    !month
        idate5(3) = nint(bufrf(3))    !day
        idate5(4) = nint(bufrf(4))    !hour
        idate5(5) = nint(bufrf(5))    !minute
        isc       = nint(bufrf(6))    !second

        call w3fs21(idate5,nmind)
        t4dv=(real(nmind-iwinbgn,r_kind) + real(isc,r_kind)/r60)/r60

        if (l4dvar) then
          if (t4dv<zero .OR. t4dv>winlen) cycle read_loop
        else
          sstime=real(nmind,r_kind) + real(isc,r_kind)/r60
          tdiff=(sstime-gstime)/r60
          if(abs(tdiff) > twind) cycle read_loop
        endif

!       Convert obs location to radians
        if (bufrf(8)>=r360) bufrf(8)=bufrf(8)-r360
        if (bufrf(8)< zero) bufrf(8)=bufrf(8)+r360

        dlon_earth = bufrf(8)*deg2rad   !convert degrees to radians
        dlat_earth = bufrf(7)*deg2rad

!       Regional case
        if(regional)then
           call tll2xy(dlon_earth,dlat_earth,dlon,dlat,outside)
           if(diagnostic_reg) then
              call txy2ll(dlon,dlat,dlon00,dlat00)
              ntest=ntest+1
              disterr=acos(sin(dlat_earth)*sin(dlat00)+cos(dlat_earth)*cos(dlat00)* &
                   (sin(dlon_earth)*sin(dlon00)+cos(dlon_earth)*cos(dlon00)))*rad2deg
              disterrmax=max(disterrmax,disterr)
           end if
           if(outside) cycle read_loop

!       Global case
        else
           dlat = dlat_earth
           dlon = dlon_earth
           call grdcrd(dlat,1,rlats,nlat,1)
           call grdcrd(dlon,1,rlons,nlon,1)
        endif

!       Set common predictor parameters

        if (l4dvar) then
          crit1 = 0.01_r_kind
        else
          timedif = r6*abs(tdiff)        ! range:  0 to 18
!         Compute "score" for observation.  All scores>=0.0.  Lowest score is "best"
          crit1 = 0.01_r_kind+timedif 
        endif

!       Map obs to thinning grid
        call map2tgrid(dlat_earth,dlon_earth,dist1,crit1,itx,ithin,itt,iuse,sis)
        if(.not. iuse)cycle read_loop


!       "Score" observation.   We use this information to id "best" obs.

!       Locate the observation on the analysis grid.  Get sst and land/sea/ice
!       mask.  

!     isflg    - surface flag
!                0 sea
!                1 land
!                2 sea ice
!                3 snow
!                4 mixed                          

        call deter_sfc_type(dlat_earth,dlon_earth,tdiff,isflg,tsavg)

!test
        pred=zero
!test        
!       Compute "score" for observation.  All scores>=0.0.  Lowest score is "best"
        crit1 = crit1+pred + rlndsea(isflg) 

        call finalcheck(dist1,crit1,itx,iuse)

        if(.not. iuse)cycle read_loop

!       Interpolate hi-res sst analysis to observation location
        dlat_sst = dlat_earth
        dlon_sst = dlon_earth
        call grdcrd(dlat_sst,1,rlats_sst,nlat_sst,1)
        call grdcrd(dlon_sst,1,rlons_sst,nlon_sst,1)

        klon1=int(dlon_sst); klat1=int(dlat_sst)
        dx  =dlon_sst-klon1; dy  =dlat_sst-klat1
        dx1 =one-dx;         dy1 =one-dy
        w00=dx1*dy1; w10=dx1*dy; w01=dx*dy1; w11=dx*dy

        klat1=min(max(1,klat1),nlat_sst); klon1=min(max(0,klon1),nlon_sst)
        if(klon1==0) klon1=nlon_sst
        klatp1=min(nlat_sst,klat1+1); klonp1=klon1+1
        if(klonp1==nlon_sst+1) klonp1=1

        sst_hires=w00*sst_an(klat1,klon1 ) + w10*sst_an(klatp1,klon1 ) + &
                  w01*sst_an(klat1,klonp1) + w11*sst_an(klatp1,klonp1)


!       Transfer information to work array

        data_all(1, itx) = bufrf(9)            ! satellite id
        data_all(2, itx) = t4dv                ! time (hours)
        data_all(3, itx) = dlon                ! grid relative longitude
        data_all(4, itx) = dlat                ! grid relative latitude
        data_all(5, itx) = bufrf(10)*deg2rad   ! satellite zenith angle (radians)
        data_all(6, itx) = bmiss               ! satellite azimuth angle
        data_all(7, itx) = bufrf(14)           ! Navy SST retrieval
        data_all(8, itx) = zero                ! scan position (unavailable)
        data_all(9, itx) = bufrf(11)           ! solar zenith angle (radians)
        data_all(10,itx) = bufrf(12)           ! solar azimuth angle (radians)

        data_all(30,itx) = dlon_earth          ! earth relative longitude (rad)
        data_all(31,itx) = dlat_earth          ! earth relative latitude (rad)
        data_all(32,itx) = bufrf(13)           ! Data type: 151=day,152=night,159=cloud problem
        data_all(33,itx) = sst_hires           ! interpolated hires SST (deg K)

        data_all(34,itx) = val_avhrr
        data_all(35,itx) = itt

        do k=1,nchanl
           data_all(k+maxinfo,itx)= bufrf(16+k)  ! Tb for avhrr ch-3, ch-4 and ch-5
        end do



!    End of satellite read block

    end do read_loop

 end do                      ! if ( ierrmg == 0 ) then

 write(6,*) 'READ_AVHRR_NAVY:  total number of obs, nread,ndata : ',nread,ndata

! Normal exit
700 continue

  call combine_radobs(mype,mype_sub,mype_root,npe_sub,mpi_comm_sub,&
       nele,itxmax,nread,ndata,data_all,score_crit)


! Now that we've identified the "best" observations, pull out best obs
! and write them to the output file

 do n=1,ndata
    do k=1,nchanl
       if(data_all(k+maxinfo,n) > tbmin .and. &
          data_all(k+maxinfo,n) < tbmax)nodata=nodata+1
    end do
    itt=nint(data_all(maxinfo,n))
    super_val(itt)=super_val(itt)+val_avhrr
    tdiff = data_all(2,n)                ! time (hours)
    dlon=data_all(3,n)                   ! grid relative longitude
    dlat=data_all(4,n)                   ! grid relative latitude
    dlon_earth = data_all(30,n)  ! earth relative longitude (degrees)
    dlat_earth = data_all(31,n)  ! earth relative latitude (degrees)
    call deter_sfc(dlat,dlon,dlat_earth,dlon_earth,tdiff,isflg,idomsfc,sfcpct, &
            ts,tsavg,vty,vfr,sty,stp,sm,sn,zz,ff10,sfcr)
    data_all(11,n) = sfcpct(0)           ! sea percentage of
    data_all(12,n) = sfcpct(1)           ! land percentage
    data_all(13,n) = sfcpct(2)           ! sea ice percentage
    data_all(14,n) = sfcpct(3)           ! snow percentage
    data_all(15,n)= ts(0)                ! ocean skin temperature
    data_all(16,n)= ts(1)                ! land skin temperature
    data_all(17,n)= ts(2)                ! ice skin temperature
    data_all(18,n)= ts(3)                ! snow skin temperature
    data_all(19,n)= tsavg                ! average skin temperature
    data_all(20,n)= vty                  ! vegetation type
    data_all(21,n)= vfr                  ! vegetation fraction
    data_all(22,n)= sty                  ! soil type
    data_all(23,n)= stp                  ! soil temperature
    data_all(24,n)= sm                   ! soil moisture
    data_all(25,n)= sn                   ! snow depth
    data_all(26,n)= zz                   ! surface height
    data_all(27,n)= idomsfc + 0.001      ! dominate surface type
    data_all(28,n)= sfcr                 ! surface roughness
    data_all(29,n)= ff10                 ! ten meter wind factor
    data_all(30,n)= data_all(30,n)*rad2deg  ! earth relative longitude (degrees)
    data_all(31,n)= data_all(31,n)*rad2deg  ! earth relative latitude (degrees)

 end do

! Write retained data to local file
 write(lunout) obstype,sis,maxinfo,nchanl,ilat,ilon
 write(lunout) ((data_all(k,n),k=1,nele),n=1,ndata)

! Deallocate local arrays
 deallocate(data_all)

! Deallocate arrays
900 continue
 call destroygrids
 call closbf(lnbufr)

 if(diagnostic_reg.and.ntest.gt.0) write(6,*)'READ_AVHRR_NAVY:  ',&
      'mype,ntest,disterrmax=',mype,ntest,disterrmax

! End of routine
 return
end subroutine read_avhrr_navy
