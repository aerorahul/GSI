subroutine model2control(rval,bval,grad)
!$$$  subprogram documentation block
!
! abstract:  Converts variables from physical space to control space
!            This is also the adjoint of control2model
!
! program history log:
!   2007-04-16  tremolet - initial code
!   2007-04-27  tremolet - multiply by sqrt(B)^T (from ckerror_ad D. Parrish)
!   2008-12-04  todling  - update interface to ckgcov_ad; add tsen and p3d
!   2008-12-29  todling  - add call to strong balance contraint
!
!   input argument list:
!     rval - State variable
!   output argument list:
!     grad - Control variable
!
!$$$
use kinds, only: r_kind,i_kind
use constants, only: zero
use control_vectors
use state_vectors
use bias_predictors
use gsi_4dvar, only: nsubwin, lsqrtb
use gridmod, only: lat2,lon2,nsig,nsig1o,periodic
use berror, only: varprd,fpsproj
use balmod, only: tbalance,strong_bk_ad
use mpimod, only: levs_id
use jfunc, only: nsclen,npclen,nrclen,nval_lenz
use mpl_allreducemod, only: mpl_allreduce
implicit none

! Declare passed variables
type(state_vector)  , intent(inout) :: rval(nsubwin)
type(predictors)    , intent(in)    :: bval
type(control_vector), intent(inout) :: grad

! Declare local variables
real(r_kind),dimension(lat2,lon2,nsig) :: workst,workvp,workrh
integer(i_kind) :: ii,jj,kk,nnn,iflg
real(r_kind) :: zwork(nrclen)
real(r_kind) :: gradz(nval_lenz)

!******************************************************************************

if (.not.lsqrtb) call abor1('model2control: assumes lsqrtb')

! Determine how many vertical levels each mpi task will
! handle in the horizontal smoothing
nnn=0
do kk=1,nsig1o
   if (levs_id(kk)/=0) nnn=nnn+1
end do

! Loop over control steps
do jj=1,nsubwin

  workst(:,:,:)=zero
  workvp(:,:,:)=zero
  workrh(:,:,:)=zero

! Convert RHS calculations for u,v to st/vp for application of
! background error
  call getstvp(rval(jj)%u,rval(jj)%v,workst,workvp)

! Calculate sensible temperature
  call tv_to_tsen_ad(rval(jj)%t,rval(jj)%q,rval(jj)%tsen)

! Adjoint of convert input normalized RH to q to add contribution of moisture
! to t, p , and normalized rh
  call normal_rh_to_q_ad(workrh,rval(jj)%t,rval(jj)%p3d,rval(jj)%q)

! Adjoint to convert ps to 3-d pressure
  call getprs_ad(rval(jj)%p,rval(jj)%t,rval(jj)%p3d)

! Multiply by sqrt of background error adjoint (ckerror_ad)
! -----------------------------------------------------------------------------

! Apply transpose of strong balance constraint
  call strong_bk_ad(workst,workvp,rval(jj)%p, &
                    rval(jj)%t,rval(jj)%oz,rval(jj)%cw)

! Transpose of balance equation
  call tbalance(rval(jj)%t,rval(jj)%p,workst,workvp,fpsproj)

! Apply variances, as well as vertical & horizontal parts of background error
  gradz(:)=zero

  call ckgcov_ad(gradz,workst,workvp,rval(jj)%t,rval(jj)%p,workrh,&
                 rval(jj)%oz,rval(jj)%sst,rval(jj)%cw,nnn)

  do ii=1,nval_lenz
    grad%step(jj)%values(ii)=grad%step(jj)%values(ii)+gradz(ii)
  enddo

! -----------------------------------------------------------------------------

end do

! Bias predictors are duplicated
do ii=1,nsclen
  zwork(ii)=bval%predr(ii)
enddo
do ii=1,npclen
  zwork(nsclen+ii)=bval%predp(ii)
enddo

call mpl_allreduce(nrclen,zwork)

do ii=1,nsclen
  grad%predr(ii)=grad%predr(ii)+zwork(ii)*sqrt(varprd(ii))
enddo
do ii=1,npclen
  grad%predp(ii)=grad%predp(ii)+zwork(nsclen+ii)*sqrt(varprd(nsclen+ii))
enddo

return
end subroutine model2control
