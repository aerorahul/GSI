subroutine inttcp(tcphead,rp,sp)
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    inttcp       apply nonlin qc obs operator for tcps
!   prgmmr: kleist            org: np23                date: 2009-02-02
!
! abstract: apply observation operator and adjoint for tcps observations
!
! program history log:
!   2009-02-02  kleist
!
!   input argument list:
!     tcphead - obs type pointer to obs structure
!     sp      - ps increment in grid space
!
!   output argument list:
!     tcphead - obs type pointer to obs structure
!     rp      - ps results from observation operator
!
! attributes:
!   language: f90
!   machine:  ibm RS/6000 SP
!
!$$$

  use kinds, only: r_kind,i_kind
  use constants, only: half,one,two,zero,tiny_r_kind,cg_term,r3600
  use obsmod, only: tcp_ob_type,lsaveobsens,l_do_adjoint
  use qcmod, only: nlnqc_iter,c_varqc
  use gridmod, only: latlon11
  use jfunc, only: iter,jiter,niter_no_qc,jiterstart,xhat_dt,dhat_dt,l_foto
  implicit none

! Declare passed variables
  type(tcp_ob_type),pointer,intent(in):: tcphead
  real(r_kind),dimension(latlon11),intent(in):: sp
  real(r_kind),dimension(latlon11),intent(inout):: rp

! Declare local variables
  integer(i_kind) i,j1,j2,j3,j4
! real(r_kind) penalty
  real(r_kind) cg_ps,val,p0,grad,wnotgross,wgross,ps_pg,varqc_iter
  real(r_kind) w1,w2,w3,w4,time_tcp
  type(tcp_ob_type), pointer :: tcpptr

  tcpptr => tcphead
  do while (associated(tcpptr))
     j1=tcpptr%ij(1)
     j2=tcpptr%ij(2)
     j3=tcpptr%ij(3)
     j4=tcpptr%ij(4)
     w1=tcpptr%wij(1)
     w2=tcpptr%wij(2)
     w3=tcpptr%wij(3)
     w4=tcpptr%wij(4)
     
!    Forward model
     val=w1* sp(j1)+w2* sp(j2)+w3* sp(j3)+w4* sp(j4)
     if(l_foto)then
       time_tcp=tcpptr%time
       val=val+ &
        (w1*xhat_dt%p3d(j1)+w2*xhat_dt%p3d(j2)+ &
         w3*xhat_dt%p3d(j3)+w4*xhat_dt%p3d(j4))*time_tcp
     end if

     if (lsaveobsens) then
       tcpptr%diags%obssen(jiter) = val*tcpptr%raterr2*tcpptr%err2
     else
       if (tcpptr%luse) tcpptr%diags%tldepart(jiter)=val
     endif

     if(l_do_adjoint)then
       if (lsaveobsens) then
         grad = tcpptr%diags%obssen(jiter)

       else
         val=val-tcpptr%res
!        gradient of nonlinear operator
!        Gradually turn on variational qc to avoid possible convergence problems
         if (nlnqc_iter .and. tcpptr%pg > tiny_r_kind .and.  &
                              tcpptr%b  > tiny_r_kind) then
            cg_ps=cg_term/tcpptr%b                           ! b is d in Enderson
            wnotgross= one-ps_pg                            ! pg is A in Enderson
            wgross =ps_pg*cg_ps/wnotgross                   ! wgross is gama in Enderson
            p0=wgross/(wgross+exp(-half*tcpptr%err2*val**2)) ! p0 is P in Enderson
            val=val*(one-p0)                                ! term is Wqc in Enderson
         endif

         grad     = val*tcpptr%raterr2*tcpptr%err2
       end if

!      Adjoint
       rp(j1)=rp(j1)+w1*grad
       rp(j2)=rp(j2)+w2*grad
       rp(j3)=rp(j3)+w3*grad
       rp(j4)=rp(j4)+w4*grad
  
       if (l_foto) then
         grad=grad*time_tcp
         dhat_dt%p3d(j1)=dhat_dt%p3d(j1)+w1*grad
         dhat_dt%p3d(j2)=dhat_dt%p3d(j2)+w2*grad
         dhat_dt%p3d(j3)=dhat_dt%p3d(j3)+w3*grad
         dhat_dt%p3d(j4)=dhat_dt%p3d(j4)+w4*grad
       endif

     end if
     tcpptr => tcpptr%llpoint
  end do
  return
end subroutine inttcp
