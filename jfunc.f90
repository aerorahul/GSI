module jfunc
!$$$   module documentation block
!                .      .    .                                       .
! module:    jfunc
!   prgmmr: treadon          org: np23                date: 2003-11-24
!
! abstract: module containing variables used in inner loop minimzation
!
! program history log:
!   2003-11-24  treadon
!   2004-05-18  kleist, documentation
!   2004-10-06  kleist, create separate control vector for u,v
!   2004-10-15  parrish, add outer iteration variable for nonlinear qc
!   2004-12-23  treadon - add logical flags first and last
!   2005-02-23  wu - add qoption, dqdt,dqdrh,dqdp and varq for norm RH
!   2005-03-28  wu - replace mlath with mlat             
!   2005-06-03  parrish - add logical switch_on_derivatives
!   2005-09-29  kleist - add pointers for time derivatives
!   2005-11-21  kleist - expand time deriv pointers for tracer tendencies
!   2005-11-29  derber - fix bug in restart
!   2006-02-02  treadon - remove prsi_oz (use ges_prsi array)
!   2006-08-30  zhang,b - add bias correction control parameter
!   2007-03-13  derber - remove qsinv2 and add rhgues
!   2007-04-13  tremolet - use control vectors
!   2008-05-22  guo, j - merge GMAO MERRA changes with NCEP 2008-04-22
!                      - defer GMAO diurnal bias correction changes.
!   2008-12-01  todling - bring in Tremolet's changes
!
! Subroutines Included:
!   init_jfunc           - set defaults for cost function variables
!   create_jfunc         - allocate cost function arrays 
!   destroy_jfunc        - deallocate cost function arrays
!   read_guess_solution  - read guess solution
!   write_guess_solution - write guess solution
!   strip2               - strip off halo from subdomain arrays
!   set_pointer          - set location indices for components of vectors
!
! remarks: variable definitions below
!   def first      - logical flag = .true. on first outer iteration
!   def last       - logical flag = .true. following last outer iteration
!   def switch_on_derivatives - .t. = generate horizontal derivatives
!   def iout_iter  - output file number for iteration information
!   def miter      - number of outer iterations
!   def qoption    - option of q analysis variable; 1:q/qsatg 2:norm RH
!   def iguess     - flag for guess solution
!   def biascor    - background error bias correction coefficient 
!   def bcoption   - 0=ibc (no bias correction to bkg); 1= sbc(original implementation)
!   def diurnalbc  - 1= diurnal bias; 0= persistent bias
!   def niter      - number of inner interations (for each other iter.)
!   def niter_no_qc- number of inner interations without nonlinear qc (for each outer iter.)
!   def jiter      - outer iteration counter
!   def jiterstart - first outloop iteration number
!   def jiterend   - last outloop iteration number
!   def iter       - do loop iteration integer
!   def nclen      - length of control (x,y) vectors
!   dev nuvlen     - length of special control vector for u,v
!   dev ntendlen   - length of special control vector for ut,vt,tt,pst (tlm time tendencies)
!   def nvals_levs - number of 2d (x/y) state-vector variables
!   def nvals_len  - number of 2d state-vector variables * subdomain size (with buffer)
!   def nval_levs  - number of 2d (x/y) control-vector variables
!   def nval_len   - number of 2d control-vector variables * subdomain size (with buffer)
!   def nstsm      - starting point for streamfunction in control vector for comm.
!                    from here on down, without buffer points
!   def nvpsm      - starting point for velocity pot. in control vector for comm.
!   def npsm       - starting point for ln(ps) in control vector for comm.
!   def ntsm       - starting point for temperature in control vector for comm.
!   def nqsm       - starting point for moisture in control vector for comm.
!   def nozsm      - starting point for ozone in control vector for comm.
!   def nsstsm     - starting point for sst in control vector for comm.
!   def nsltsm     - starting point for skin/land temp. in control vector for comm.
!   def nsitsm     - starting point for skin/ice temp. in control vector for comm.
!   def ncwsm      - starting point for cloud water in control vector for comm.
!   def nst2       - starting point for streamfunction in control vector for comm.
!                    from here on down, including buffer points
!   def nvp2       - starting point for velocity pot. in control vector for comm.
!   def np2        - starting point for ln(ps) in control vector for comm.
!   def nt2        - starting point for temperature in control vector for comm.
!   def nq2        - starting point for moisture in control vector for comm.
!   def noz2       - starting point for ozone in control vector for comm.
!   def nsst2      - starting point for sst in control vector for comm.
!   def nslt2      - starting point for skin/land temp. in control vector for comm.
!   def nsit2      - starting point for skin/ice temp. in control vector for comm.
!   def ncw2       - starting point for cloud water in control vector for comm.
!   def l_foto     - option for foto
!
! attributes:
!   language: f90
!   machine:  ibm RS/6000 SP
!
!$$$
  use kinds, only: r_kind,i_kind
  use control_vectors 
  use state_vectors
  implicit none

  logical first,last,switch_on_derivatives,tendsflag,l_foto
  integer(i_kind) iout_iter,miter,iguess,nclen,qoption
  integer(i_kind) jiter,jiterstart,jiterend,iter
  integer(i_kind) nt,nq,noz,ncw,np,nsst,nst,nvp,nu,nv
  integer(i_kind) nvals_len,nvals_levs
  integer(i_kind) nval_len,nval_lenz,nval_levs
  integer(i_kind) nut,nvt,ntt,nprst,nqt,nozt,ncwt,ndivt,nagvt
  integer(i_kind) nstsm,nvpsm,npsm,ntsm,nqsm,nozsm,nsstsm,nsltsm,nsitsm,ncwsm
  integer(i_kind) nst2,nvp2,np2,nt2,nq2,noz2,nsst2,nslt2,nsit2,ncw2
  integer(i_kind) nclen1,nclen2,nrclen,nsclen,npclen,nuvlen,ntendlen
  integer(i_kind) nval2d,nclenz
  integer(i_kind),dimension(0:50):: niter,niter_no_qc
  real(r_kind) factqmax,factqmin,gnormorig,penorig,biascor,diurnalbc
  integer(i_kind) bcoption
  real(r_kind),allocatable,dimension(:,:,:):: qsatg,rhgues,qgues,dqdt,dqdrh,dqdp 
  real(r_kind),allocatable,dimension(:,:):: varq
  type(control_vector),save :: xhatsave,yhatsave,xhatsave_r,yhatsave_r
  type(state_vector),save ::xhat_dt,dhat_dt

contains

  subroutine init_jfunc
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    init_jfunc
!   prgmmr: treadon          org: np23               date:  2003-11-24
!
! abstract: initialize cost function variables to defaults
!
! program history log:
!   2003-11-24  treadon
!   2004-05-18  kleist, documentation
!   2004-12-23  treadon - initialize first and last
!   2005-06-03  parrish - initialize switch_on_derivatives
!   2005-10-27  kleist  - initialize tendency flag
!   2006-08-30  zhang,b - initialize bias correction scheme
!   2008-05-12  safford - rm unused uses
!
!   input argument list:
!
!   output argument list:
!
! attributes:
!   language: f90
!   machine:  ibm rs/6000 sp
!
!$$$
    use constants, only: zero, one
    implicit none
    integer(i_kind) i

    first = .true.
    last  = .false.
    switch_on_derivatives=.false.
    tendsflag=.false.
    l_foto=.false.

    factqmin=one
    factqmax=one
    iout_iter=220
    miter=1
    qoption=1
    do i=0,50
      niter(i)=0
      niter_no_qc(i)=1000000
    end do
    jiterstart=1
    jiterend=1
    jiter=jiterstart
    biascor=-one        ! bias multiplicative coefficient
    diurnalbc=0         ! 1= diurnal bias; 0= persistent bias
    bcoption=1          ! 0=ibc; 1=sbc
    nclen=1
    nclenz=1
    nuvlen=1
    ntendlen=1

    penorig=zero
    gnormorig=zero

! iguess = -1  do not use guess file
! iguess =  0  write only guess file
! iguess =  1  read and write guess file
! iguess =  2  read only guess file

    iguess=1  

    return
  end subroutine init_jfunc

  subroutine create_jfunc(mlat)
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    create_jfunc
!   prgmmr: treadon          org: np23               date:  2003-11-24
!
! abstract: allocate memory for cost function variables
!
! program history log:
!   2003-11-24  treadon
!   2004-05-18  kleist, documentation
!   2004-07-28  treadon - simplify subroutine argument list
!   2005-03-28  wu - replace mlath with mlat, modify dim of varq 
!   2005-06-15  treadon - remove "use guess_grids"
!   2008-05-12  safford - rm unused uses
!
!   input argument list:
!
!   output argument list:
!
! attributes:
!   language: f90
!   machine:  ibm rs/6000 sp
!
!$$$
    use constants, only: zero
    use gridmod, only: lat2,lon2,nsig
    use m_berror_stats,only : berror_get_dims
    implicit none
    integer(i_kind),intent(in)::mlat

    integer(i_kind) i,j,k

    call allocate_cv(xhatsave)
    call allocate_cv(yhatsave)
    allocate(qsatg(lat2,lon2,nsig),&
         dqdt(lat2,lon2,nsig),dqdrh(lat2,lon2,nsig),&
         varq(1:mlat,1:nsig),dqdp(lat2,lon2,nsig),&
         rhgues(lat2,lon2,nsig),qgues(lat2,lon2,nsig))

    xhatsave=zero
    yhatsave=zero

    if (iguess>0) then
      call allocate_cv(xhatsave_r)
      call allocate_cv(yhatsave_r)
      xhatsave_r=zero
      yhatsave_r=zero
    endif

    do k=1,nsig
       do j=1,mlat
         varq(j,k)=zero
       end do
    end do

    do k=1,nsig
       do j=1,lon2
          do i=1,lat2
             qsatg(i,j,k)=zero
             dqdt(i,j,k)=zero
             dqdrh(i,j,k)=zero
             dqdp(i,j,k)=zero
             qgues(i,j,k)=zero
             rhgues(i,j,k)=zero
          end do
       end do
    end do

    return
  end subroutine create_jfunc
    
  subroutine destroy_jfunc
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    destroy_jfunc
!   prgmmr: treadon          org: np23               date:  2003-11-24
!
! abstract: deallocate memory from cost function variables
!
! program history log:
!   2003-11-24  treadon
!   2004-05-18  kleist, documentation
!
!   input argument list:
!
!   output argument list:
!
! attributes:
!   language: f90
!   machine:  ibm rs/6000 sp
!
!$$$
    call deallocate_cv(xhatsave)
    call deallocate_cv(yhatsave)
    deallocate(varq)
    deallocate(dqdt,dqdrh,dqdp,qsatg,qgues,rhgues)

! NOTE:  xhatsave_r and yhatsave_r are deallocated in
!        pcgsoi following transfer of their contents
!        to xhatsave and yhatsave.  The deallocate is
!        releases this memory since it is no longer needed.

    return
  end subroutine destroy_jfunc

  subroutine read_guess_solution(mype)
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    read_guess_solution
!   prgmmr: treadon          org: np23               date:  2003-11-24
!
! abstract: read in guess solution
!
! program history log:
!   2003-11-24  treadon
!   2004-05-18  kleist, documentation
!   2005-05-05  treadon - read guess solution from 4-byte reals
!   2008-05-12  safford - rm unused uses and vars
!
!   input argument list:
!     mype   - mpi task id
!
!   output argument list:
!
! attributes:
!   language: f90
!   machine:  ibm rs/6000 sp
!
!$$$
    use kinds, only: r_single
    use mpimod, only: ierror, mpi_comm_world,mpi_real4
    use gridmod, only: nlat,nlon,nsig,itotsub,ltosi_s,ltosj_s,&
         displs_s,ijn_s,latlon11,iglobal
    use obsmod, only: iadate
    implicit none

    integer(i_kind),intent(in):: mype

    integer(i_kind) i,k,mm1,myper,kk,i1,i2
    integer(i_kind) nlatg,nlong,nsigg
    integer(i_kind),dimension(5):: iadateg
    real(r_single),dimension(max(iglobal,itotsub)):: fieldx,fieldy
    real(r_single),dimension(nlat,nlon):: xhatsave_g,yhatsave_g
    real(r_single),dimension(nclen):: xhatsave_r4,yhatsave_r4
    
    jiterstart = 1
    mm1=mype+1
    myper=0

! Open unit to guess solution.  Read header.  If no header, file is
! empty and exit routine
    open(12,file='gesfile_in',form='unformatted')
    iadateg=0
    nlatg=0
    nlong=0
    nsigg=0
    read(12,end=1234)iadateg,nlatg,nlong,nsigg
    if(iadate(1) == iadateg(1) .and. iadate(2) == iadate(2) .and. &
          iadate(3) == iadateg(3) .and. iadate(4) == iadateg(4) .and. &
          iadate(5) == iadateg(5) .and. nlat == nlatg .and. &
          nlon == nlong .and. nsig == nsigg) then
      if(mype == 0) write(6,*)'READ_GUESS_SOLUTION:  read guess solution for ',&
                    iadateg,nlatg,nlong,nsigg
      jiterstart=0
         
! Let all tasks read gesfile_in to pick up bias correction (second read)

! Loop to read input guess fields.  After reading in each field & level,
! scatter the grid to the appropriate location in the xhat and yhatsave
! arrays.
      do k=1,nval_levs
        read(12,end=1236) xhatsave_g,yhatsave_g
        do kk=1,itotsub
          i1=ltosi_s(kk); i2=ltosj_s(kk)
          fieldx(kk)=xhatsave_g(i1,i2)
          fieldy(kk)=yhatsave_g(i1,i2)
        end do
        i=(k-1)*latlon11 + 1
        call mpi_scatterv(fieldx,ijn_s,displs_s,mpi_real4,&
                 xhatsave_r4(i),ijn_s(mm1),mpi_real4,myper,mpi_comm_world,ierror)
        call mpi_scatterv(fieldy,ijn_s,displs_s,mpi_real4,&
                 yhatsave_r4(i),ijn_s(mm1),mpi_real4,myper,mpi_comm_world,ierror)
      end do  !end do over nval_levs

!     Read radiance and precipitation bias correction terms
      read(12,end=1236) (xhatsave_r4(i),i=nclen1+1,nclen),(yhatsave_r4(i),i=nclen1+1,nclen)
      do i=1,nclen
         xhatsave_r%values(i)=xhatsave_r4(i)
         yhatsave_r%values(i)=yhatsave_r4(i)
      end do
         
    else
      if(mype == 0) then
        write(6,*) 'READ_GUESS_SOLUTION:  INCOMPATABLE GUESS FILE, gesfile_in'
        write(6,*) 'READ_GUESS_SOLUTION:  iguess,iadate,iadateg=',iguess,iadate,iadateg
        write(6,*) 'READ_GUESS_SOLUTION:  nlat,nlatg,nlon,nlong,nsig,nsigg=',&
                    nlat,nlatg,nlon,nlong,nsig,nsigg
      end if
    endif
    close(12)
    return

! The guess file is empty.  Do not return an error code but print a message to
! standard out.
1234  continue
    if(mype == 0) then
      write(6,*) 'READ_GUESS_SOLUTION:  NO GUESS FILE, gesfile_in'
      write(6,*) 'READ_GUESS_SOLUTION:  iguess,iadate,iadateg=',iguess,iadate,iadateg
      write(6,*) 'READ_GUESS_SOLUTION:  nlat,nlatg,nlon,nlong,nsig,nsigg=',&
                  nlat,nlatg,nlon,nlong,nsig,nsigg
    end if
    close(12)
    return

! Error contition reading level or bias correction data.  Set error flag and
! return to the calling program.
1236  continue
    if (mype==0) write(6,*) 'READ_GUESS_SOLUTION:  ERROR in reading guess'
    close(12)
    call stop2(76)

    return
  end subroutine read_guess_solution
  
  subroutine write_guess_solution(mype)
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    write_guess_solution
!   prgmmr: treadon          org: np23               date:  2003-11-24
!
! abstract: write out guess solution (not from spectral forecast)
!
! program history log:
!   2003-11-24  treadon
!   2004-05-18  kleist, documentation
!   2005-03-10  treadon - remove iadate from calling list, access via obsmod
!   2005-05-05  treadon - write guess solution using 4-byte reals
!   2008-05-12  safford - rm unused uses
!   2008-12-13  todling - strip2 called w/ consistent interface
!
!   input argument list:
!     mype   - mpi task id
!
!   output argument list:
!
! attributes:
!   language: f90
!   machine:  ibm rs/6000 sp
!
!$$$
    use kinds, only: r_single
    use mpimod, only: ierror, mpi_comm_world, mpi_rtype,mpi_real4
    use gridmod, only: ijn,latlon11,displs_g,ltosj,ltosi,nsig,&
         nlat,nlon,lat1,lon1,itotsub,iglobal
    use obsmod, only: iadate
    use constants, only: zero
    implicit none

    integer(i_kind),intent(in):: mype

    integer(i_kind) i,j,k,mm1,mypew,kk,i1,i2,ie,is
    real(r_single),dimension(lat1,lon1,2):: field
    real(r_single),dimension(max(iglobal,itotsub)):: fieldx,fieldy
    real(r_single),dimension(nlat,nlon):: xhatsave_g,yhatsave_g
    real(r_single),dimension(nrclen):: xhatsave4,yhatsave4

    mm1=mype+1
    mypew=0
    
! Write header record to output file
    if (mype==mypew) then
      open(51,file='gesfile_out',form='unformatted')
      write(51) iadate,nlat,nlon,nsig
    endif

! Loop over levels.  Gather guess solution and write to output
    do k=1,nval_levs
      ie=(k-1)*latlon11 + 1
      is=ie+latlon11
      call strip2(xhatsave%values(ie:is),yhatsave%values(ie:is),field)
      call mpi_gatherv(field(1,1,1),ijn(mm1),mpi_real4,&
           fieldx,ijn,displs_g,mpi_real4,mypew,&
           mpi_comm_world,ierror)
      call mpi_gatherv(field(1,1,2),ijn(mm1),mpi_real4,&
           fieldy,ijn,displs_g,mpi_real4,mypew,&
           mpi_comm_world,ierror)

! Transfer to global arrays
      do j=1,nlon
        do i=1,nlat
          xhatsave_g(i,j)=zero
          yhatsave_g(i,j)=zero
        end do
      end do
      do kk=1,iglobal
        i1=ltosi(kk); i2=ltosj(kk)
        xhatsave_g(i1,i2)=fieldx(kk)
        yhatsave_g(i1,i2)=fieldy(kk)
      end do

! Write level record
      if (mype==mypew) write(51) xhatsave_g,yhatsave_g
    end do  !end do over nval_levs

! Write radiance and precipitation bias correction terms to output file
    if (mype==mypew) then
       do i=1,nrclen
          xhatsave4(i)=xhatsave%values(nclen1+i)
          yhatsave4(i)=yhatsave%values(nclen1+i)
       end do
      write(51) (xhatsave4(i),i=1,nrclen),(yhatsave4(i),i=1,nrclen)
      close(51)
      write(6,*)'WRITE_GUESS_SOLUTION:  write guess solution for ',&
                 iadate,nlat,nlon,nsig
    endif

    return
  end subroutine write_guess_solution

    subroutine strip2(field_in1,field_in2,field_out)
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    strip2
!   prgmmr: treadon          org: np23                date: 2003-11-24
!
! abstract: strip off halo from two subdomain arrays & combine into
!           single output array
!
! program history log:
!   2003-11-24  treadon
!   2004-05-18  kleist, documentation
!   2008-05-12  safford - rm unused uses
!
!   input argument list:
!     field_in1 - subdomain field one with halo
!     field_in2 - subdomain field two with halo
!
!   output argument list:
!     field_out - combined subdomain fields with halo stripped
!
! attributes:
!   language: f90
!   machine:  ibm rs/6000 sp
!
!$$$
    use kinds, only: r_single
    use gridmod, only: lat1,lon1,lat2,lon2
    implicit none

    integer(i_kind) i,j,jp1
    real(r_single),dimension(lat1,lon1,2):: field_out
    real(r_kind),dimension(lat2,lon2):: field_in1,field_in2

    do j=1,lon1
      jp1 = j+1
      do i=1,lat1
        field_out(i,j,1)=field_in1(i+1,jp1)
        field_out(i,j,2)=field_in2(i+1,jp1)
      end do
    end do

    return
  end subroutine strip2

  subroutine set_pointer
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    set_pointer
!   prgmmr: treadon          org: np23                date: 2004-07-28
!
! abstract: Set length of control vector and other control 
!           vector constants
!
! program history log:
!   2004-07-28  treadon
!   2006-04-21  kleist - include pointers for more time tendency arrays
!   2008-12-04  todling - increase number of 3d fields from 6 to 8 
!
!   input argument list:
!
!   output argument list:
!
! attributes:
!   language: f90
!   machine:  ibm rs/6000 sp
!
!$$$
    use gridmod, only: lat1,lon1,latlon11,latlon1n,nsig,lat2,lon2
    use gridmod, only: nsig1o,regional,nlat,nlon
    use radinfo, only: npred,jpch_rad
    use pcpinfo, only: npredp,npcptype
    use gsi_4dvar, only: nsubwin, lsqrtb
    use bias_predictors, only: setup_predictors
    use control_vectors, only: setup_control_vectors
    use state_vectors, only: setup_state_vectors
    implicit none

    integer(i_kind) nx,ny,mr,nr,nf

    nvals_levs=8*nsig+2+1         ! +1 for extra level in p3d
    nvals_len=nvals_levs*latlon11

    nval_levs=6*nsig+2
    nval_len=nval_levs*latlon11
    nsclen=npred*jpch_rad
    npclen=npredp*npcptype
    nclen=nsubwin*nval_len+nsclen+npclen
    nrclen=nsclen+npclen
    nclen1=nclen-nrclen
    nclen2=nclen1+nsclen
    nuvlen=2*latlon1n
    ntendlen=9*latlon1n+latlon11
  
    if(lsqrtb) then
      if(regional) then
        nval2d=nlat*nlon*3
      else
!           following lifted from subroutine create_berror_vars in module berror.f90
!            inserted because create_berror_vars called after this routine
        nx=nlon*3/2
        nx=nx/2*2
        ny=nlat*8/9
        ny=ny/2*2
        if(mod(nlat,2)/=0)ny=ny+1
        mr=0
        nr=nlat/4
        nf=nr
        nval2d=(ny*nx + 2*(2*nf+1)*(2*nf+1))*3
      end if
      nval_lenz=nval2d*nsig1o
      nclenz=nsubwin*nval_lenz+nsclen+npclen
    else
      nval2d=latlon11
    end if

    nst=1                                  ! streamfunction
    nvp=nst+latlon1n                       ! velocity potential
    nt=nvp +latlon1n                       ! t
    nq=nt  +latlon1n                       ! q
    noz=nq +latlon1n                       ! oz
    ncw=noz+latlon1n                       ! cloud water
    np=ncw +latlon1n                       ! surface pressure
    nsst=np+latlon11                       ! skin temperature

! Define pointers for isolated u,v on subdomains work vector
    nu=1                                   ! zonal wind
    nv=nu+latlon1n                         ! meridional wind

! Define pointers for isolated ut,vt,tt,qt,ozt,cwt,pst on subdomains work vector
    nut=1                                  ! zonal wind tend
    nvt=nut+latlon1n                       ! meridional wind tend
    ntt=nvt+latlon1n                       ! temperature tend
    nprst=ntt+latlon1n                     ! 3d-pressure tend (nsig+1 levs)
    nqt=nprst+latlon1n+latlon11            ! q tendency
    nozt=nqt+latlon1n                      ! ozone tendency
    ncwt=nozt+latlon1n                     ! cloud water tendency
    ndivt=ncwt+latlon1n                    ! divergence tendency
    nagvt=ndivt+latlon1n                   ! ageostrophic vorticity tendency

!   For new mpi communication, define vector starting points
!   for each variable type using the subdomains size without 
!   buffer points
    nstsm=1                                ! streamfunction small 
    nvpsm=nstsm  +(lat1*lon1*nsig)         ! vel. pot. small
    npsm=nvpsm   +(lat1*lon1*nsig)         ! sfc. p. small
    ntsm=npsm    +(lat1*lon1)              ! temp. small
    nqsm=ntsm    +(lat1*lon1*nsig)         ! q small
    nozsm=nqsm   +(lat1*lon1*nsig)         ! oz small
    nsstsm=nozsm +(lat1*lon1*nsig)         ! sst small
    nsltsm=nsstsm+(lat1*lon1)              ! land sfc. temp small
    nsitsm=nsltsm+(lat1*lon1)              ! ice sfc. temp small
    ncwsm=nsitsm +(lat1*lon1)              ! cloud water small
    
!   Define vector starting points for subdomains which include
!   buffer points
    nst2=1                               ! streamfunction mpi
    nvp2=nst2  +latlon1n                 ! vel pot mpi
    np2=nvp2   +latlon1n                 ! sfc p mpi
    nt2=np2    +latlon11                 ! temp mpi
    nq2=nt2    +latlon1n                 ! q mpi
    noz2=nq2   +latlon1n                 ! oz mpi
    nsst2=noz2 +latlon1n                 ! sst mpi
    nslt2=nsst2+latlon11                 ! sfc land temp mpi
    nsit2=nslt2+latlon11                 ! ice sfc temp mpi
    ncw2=nsit2 +latlon11                 ! cloud water mpi

    if (lsqrtb) then
      CALL setup_control_vectors(nsig,lat2,lon2,latlon11,latlon1n, &
                               & nsclen,npclen,nclenz,nsubwin,nval_lenz,lsqrtb)
    else
      CALL setup_control_vectors(nsig,lat2,lon2,latlon11,latlon1n, &
                               & nsclen,npclen,nclen,nsubwin,nval_len,lsqrtb)
    endif
    CALL setup_state_vectors(latlon11,latlon1n,nvals_len,lat2,lon2,nsig)
    CALL setup_predictors(nrclen,nsclen,npclen)

  end subroutine set_pointer
end module jfunc
