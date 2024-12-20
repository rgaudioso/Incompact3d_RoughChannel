!Copyright (c) 2012-2022, Xcompact3d
!This file is part of Xcompact3d (xcompact3d.com)
!SPDX-License-Identifier: BSD 3-Clause

module rough

  use decomp_2d_constants
  use decomp_2d_mpi
  use decomp_2d
  use variables
  use param

  implicit none

  integer :: FS
  character(len=100) :: fileformat
  character(len=1),parameter :: NL=char(10) !new line character

  PRIVATE ! All functions/subroutines private by default
  PUBLIC :: init_rough, boundary_conditions_rough, postprocess_rough, &
            visu_rough, visu_rough_init, momentum_forcing_rough, &
            geomcomplex_rough, read_roughness, axial_averaging

contains
  !############################################################################
  subroutine init_rough (ux1,uy1,uz1,ep1,phi1)

    use decomp_2d_io
    use variables
    use param
    use ibm_param, only : offset
    use MPI

    implicit none

    real(mytype),dimension(xsize(1),xsize(2),xsize(3)) :: ux1,uy1,uz1,ep1
    real(mytype),dimension(xsize(1),xsize(2),xsize(3),numscalar) :: phi1
  
    real(mytype)                    :: um,ym
    real(mytype)                    :: nu
    integer :: k,j,i,fh,ierror,ii,is,it,code, jj

    if (idir_stream /= 1 .and. idir_stream /= 3) then
       if (nrank == 0) then
          write(*,*) '!! ERROR in imposing sorce term for momentum !!'
          write(*,*) '!! idir_stream ', idir_stream
          write(*,*) '!! idir_stream has to be:'
          write(*,*) '!! - 1 for streamwise direction in X'
          write(*,*) '!! - 3 for streamwise direction in Z'
          write(*,*) '!! Y is not supported and other values do not make sense'
          write(*,*) '!! Calculation will be now stop'
        endif
        call MPI_ABORT(MPI_COMM_WORLD,code,ierror); stop
    endif
    !+++++++++++++++++++++++++++++++++ INSERIRE QUI MBC INIT PHI++++++++++++++++++++++++++++++++++++++++++++++
    if (iscalar.ne.0) then
       !Analytical laminar temperature profile, with nu=4.36
       nu=real(140./34.,8)
       if (nrank==0.and.(mod(itime, ilist) == 0 .or. itime == ifirst .or. itime == ilast)) then
          write(*,*) 'Imposing analytical laminar  temperature profile'
       endif
       do is=1,numscalar
         do k=1,xsize(3)
            do j=1,xsize(2)
             if (istret==0) ym=real(j+xstart(2)-1-1,mytype)*dy-yly*half
             if (istret/=0) ym=yp(j+xstart(2)-1)-yly*half
             !if (istret==0) ym=real(j+xstart(2)-1-1,mytype)*dy-(yly-offset)*half ! Consider here wall offset (mean roughness level)
             !if (istret/=0) ym=yp(j+xstart(2)-1)-(yly-offset)*half
               do i=1,xsize(1)
                  if (ep1(i,j,k).eq.0) then
                     phi1(i,j,k,is) = (nu/sixteen)*(five + ym**four - six*(ym**two))  
		     !phi1(i,j,k,is) = one
                  else
                     phi1(i,j,k,is) = zero
                  endif
               enddo
            enddo
         enddo
       enddo
       !if ((nclyS1 == 2).and.(xstart(2) == 1)) then
         !! Generate a hot patch on bottom boundary
       !   phi1(:,1,:,:) = zero !one
       !endif
       !if ((nclySn == 2).and.(xend(2) == ny)) then
       !   phi1(:,xsize(2),:,:) = zero
       !endif
    endif  
   !+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   !++++++++++++++++++++++++++++++++++++INIT FLOW VEL++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    ux1=zero
    uy1=zero
    uz1=zero
    byx1=zero;byy1=zero;byz1=zero
    ! if to decide type of initialization to apply 
    if (iin == 0) then ! laminar flow
       do k=1,xsize(3)
          do j=1,xsize(2)
             if (istret==0) ym=real(j+xstart(2)-1-1,mytype)*dy-yly*half
             if (istret/=0) ym=yp(j+xstart(2)-1)-yly*half
             !if (istret==0) ym=real(j+xstart(2)-1-1,mytype)*dy-(yly-offset)*half ! Consider here wall offset (mean roughness level)
             !if (istret/=0) ym=yp(j+xstart(2)-1)-(yly-offset)*half
             um=exp(-zptwo*ym*ym)
             do i=1,xsize(1)
                if (idir_stream == 1) then
		   if (iibm.ne.0) then
                      if (ep1(i,j,k).eq.0) then ! Fluid region
                         !Poiseuille flow (nondim) => u(y) = 1 - y^2/H^2
                         ux1(i,j,k)=one-ym**two
                         uy1(i,j,k)=zero
                         uz1(i,j,k)=sin(real(i-1,mytype)*dx)+cos(real(k-1,mytype)*dz)
                     else 
		         !Inside the rough walls
                         ux1(i,j,k)=zero
                         uy1(i,j,k)=zero
                         uz1(i,j,k)=zero
		     endif
                  else
                      ux1(i,j,k)=one-ym**two
                      uy1(i,j,k)=zero
                      uz1(i,j,k)=sin(real(i-1,mytype)*dx)+cos(real(k-1,mytype)*dz)
                  endif
		else
		   if (nrank == 0) then
                       write(*,*) 'ERROR: idir_stream supported only streamwise'
		       call MPI_ABORT(MPI_COMM_WORLD,code,ierror); stop
		   endif
                endif
             enddo
          enddo
       enddo     
    elseif (iin <= 2) then ! Traditional init to turbulent flows using random numbers + lam profile
       call system_clock(count=code)
       if (iin.eq.2) code=0
       call random_seed(size = ii)
       call random_seed(put = code+63946*(nrank+1)*(/ (i - 1, i = 1, ii) /))
       call random_number(ux1)
       call random_number(uy1)
       call random_number(uz1)
       !modulation of the random noise + initial velocity profile
       do k=1,xsize(3)
          do j=1,xsize(2)
             if (istret==0) ym=real(j+xstart(2)-1-1,mytype)*dy-yly*half
             if (istret/=0) ym=yp(j+xstart(2)-1)-yly*half
             !if (istret==0) ym=real(j+xstart(2)-1-1,mytype)*dy-(yly-offset)*half ! Consider here wall offset (mean roughness level)
             !if (istret/=0) ym=yp(j+xstart(2)-1)-(yly-offset)*half
             um=exp(-fifteen*ym*ym)
             do i=1,xsize(1)
                if (idir_stream == 1) then		   
                   if (iibm.ne.0) then
                      if (ep1(i,j,k).eq.0) then ! Fluid region
		         ! (y.lt.(yly-4*offset).or.y.ge.(4*offset)) ! FOR: Only centerline noise
                         !Poiseuille flow (nondim) => u(y) = 1 - y^2/H^2
                         ux1(i,j,k)=init_noise*um*(two*ux1(i,j,k)-one)+(one-ym**two)
                         uy1(i,j,k)=init_noise*um*(two*uy1(i,j,k)-one)
                         uz1(i,j,k)=init_noise*um*(two*uz1(i,j,k)-one)
                     else 
		         !Inside the rough walls
                         ux1(i,j,k)=zero
                         uy1(i,j,k)=zero
                         uz1(i,j,k)=zero
		     endif
                   else
		      !Poiseuille flow (nondim) => u(y) = 1 - y^2/H^2
                      ux1(i,j,k)=init_noise*um*(two*ux1(i,j,k)-one)+(one-ym**two)
                      uy1(i,j,k)=init_noise*um*(two*uy1(i,j,k)-one)
                      uz1(i,j,k)=init_noise*um*(two*uz1(i,j,k)-one) 
                   endif
                else
                   if (nrank == 0) then
                       write(*,*) 'ERROR: idir_stream supported only streamwise'
		       call MPI_ABORT(MPI_COMM_WORLD,code,ierror); stop
		   endif
                endif
             enddo
          enddo
       enddo
    elseif (iin == 4) then ! SEM
       call sem_init_rough(ux1, uy1, uz1)
    endif 
    !!$=====DEBUG test in SERIAL
    !if (nrank==0) then 
       ! Write the initial ux to file
    !   open(unit=98, file='ux_init.dat', status='unknown')
    !   do j=1,xsize(2)   
    !      write(98, *) ux1(1,j,1)
    !   enddo
    !   close(98)
   ! endif
   !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    return
  end subroutine init_rough
  !############################################################################
  !############################################################################
  subroutine boundary_conditions_rough (ux,uy,uz,phi)

    use param
    use var, only : di2
    use variables
    use mhd, only : Bm, mhd_active, mhd_equation 

    implicit none

    real(mytype),dimension(xsize(1),xsize(2),xsize(3)) :: ux,uy,uz
    real(mytype),dimension(xsize(1),xsize(2),xsize(3),numscalar) :: phi

    if (.not.cpg.and.iibm.eq.0 ) then ! if not constant pressure gradient
       if (idir_stream == 1) then
          call rough_cfr(ux,two/three)
       else
          call rough_cfr(uz,two/three)
       endif
    end if

    if (iscalar /= 0) then
       if (iimplicit <= 0) then
          if ((nclyS1 == 2).and.(xstart(2) == 1)) then
             !! Generate a hot patch on bottom boundary
             !phi(:,1,:,:) = one
	     !! Keep T = Tw on bottom boundary
             phi(:,1,:,:) = zero
          endif
          if ((nclySn == 2).and.(xend(2) == ny)) THEN
             phi(:,xsize(2),:,:) = zero
          endif
       else
          !
          ! Implicit boundary conditions are usually given in input file
          ! It is possible to modify g_sc here
          ! It is not possible to modify alpha_sc and beta_sc here
          !
          ! Bottom temperature if alpha_sc(:,1)=1 and beta_sc(:,1)=0 (default)
          !if (nclyS1.eq.2) g_sc(:,1) = one
          ! Top temperature if alpha_sc(:,2)=1 and beta_sc(:,2)=0 (default)
          !if (nclySn.eq.2) g_sc(:,2) = zero
       endif
    endif

    if( mhd_active .and. iimplicit<=0 .and. mhd_equation ) then
       ! FIXME add a test
       ! This is valid only when nclyB*1 = 2
       if (xstart(2) == 1) then
          Bm(:,1,:,1)  = zero
          Bm(:,1,:,2)  = zero
          Bm(:,1,:,3)  = zero
       endif
       ! FIXME add a test
       ! This is valid only when nclyB*n = 2
       if (xend(2) == ny) then
          Bm(:,xsize(2),:,1) = zero
          Bm(:,xsize(2),:,2) = zero
          Bm(:,xsize(2),:,3) = zero
       endif
    endif

  end subroutine boundary_conditions_rough
  !############################################################################
  !!
  !!  SUBROUTINE: rough_cfr
  !!      AUTHOR: Kay Schäfer
  !! DESCRIPTION: Inforces constant flow rate without need of data transposition
  !!
  !############################################################################
  subroutine rough_cfr (ux, constant)

    use MPI

    implicit none

    real(mytype), dimension(xsize(1),xsize(2),xsize(3)) :: ux
    real(mytype), intent(in) :: constant

    integer :: code, i, j, k, jloc
    real(mytype) :: can, ub, uball, coeff

    ub = zero
    uball = zero
    coeff = dy / (yly * real(xsize(1) * zsize(3), kind=mytype))

    do k = 1, xsize(3)
       do jloc = 1, xsize(2)
          j = jloc + xstart(2) - 1
          do i = 1, xsize(1)
            ub = ub + ux(i,jloc,k) / ppy(j)
          enddo
       enddo
    enddo

    ub = ub * coeff

    call MPI_ALLREDUCE(ub,uball,1,real_type,MPI_SUM,MPI_COMM_WORLD,code)

    can = - (constant - uball)

    if (nrank==0.and.(mod(itime, ilist) == 0 .or. itime == ifirst .or. itime == ilast)) &
       write(*,*) 'UT', uball, can

    do k=1,xsize(3)
      do j=1,xsize(2)
        do i=1,xsize(1)
          ux(i,j,k) = ux(i,j,k) - can
        enddo
      enddo
    enddo

  end subroutine rough_cfr
  !############################################################################
  !############################################################################
  subroutine postprocess_rough(ux1,uy1,uz1,pp3,phi1,ep1)
    use var, ONLY : nzmsize

    implicit none

    real(mytype), intent(in), dimension(xsize(1),xsize(2),xsize(3)) :: ux1, uy1, uz1, ep1
    real(mytype), intent(in), dimension(xsize(1),xsize(2),xsize(3),numscalar) :: phi1
    real(mytype), intent(in), dimension(ph1%zst(1):ph1%zen(1),ph1%zst(2):ph1%zen(2),nzmsize,npress) :: pp3

  end subroutine postprocess_rough
!################################################################################
!################################################################################
  subroutine visu_rough_init(visu_initialised)

    use decomp_2d_io, only : decomp_2d_register_variable
    use visu, only : io_name, output2D
    use mhd, only : mhd_active
    
    implicit none

    logical, intent(out) :: visu_initialised

    call decomp_2d_register_variable(io_name, "critq", 1, 0, output2D, mytype)

    if (mhd_active) then
       call decomp_2d_register_variable(io_name, "J_x", 1, 0, output2D, mytype)
       call decomp_2d_register_variable(io_name, "J_y", 1, 0, output2D, mytype)
       call decomp_2d_register_variable(io_name, "J_z", 1, 0, output2D, mytype)
       call decomp_2d_register_variable(io_name, "B_x", 1, 0, output2D, mytype)
       call decomp_2d_register_variable(io_name, "B_y", 1, 0, output2D, mytype)
       call decomp_2d_register_variable(io_name, "B_z", 1, 0, output2D, mytype)
    endif

    visu_initialised = .true.
    
  end subroutine visu_rough_init
  !############################################################################
  !!
  !!  SUBROUTINE: visu_rough
  !!      AUTHOR: FS
  !! DESCRIPTION: Performs rough-specific visualization
  !!
  !############################################################################
  subroutine visu_rough(ux1, uy1, uz1, pp3, phi1, ep1, num)

    use var, only : ux2, uy2, uz2, ux3, uy3, uz3
    use var, only : ta1,tb1,tc1,td1,te1,tf1,tg1,th1,ti1,di1
    use var, only : ta2,tb2,tc2,td2,te2,tf2,di2,ta3,tb3,tc3,td3,te3,tf3,di3
    use var, ONLY : nzmsize
    use visu, only : write_field
    use mhd, only : mhd_active,Je, Bm
    
    use ibm_param, only : ubcx,ubcy,ubcz

    implicit none

    real(mytype), intent(in), dimension(xsize(1),xsize(2),xsize(3)) :: ux1, uy1, uz1
    real(mytype), intent(in), dimension(ph1%zst(1):ph1%zen(1),ph1%zst(2):ph1%zen(2),nzmsize,npress) :: pp3
    real(mytype), intent(in), dimension(xsize(1),xsize(2),xsize(3),numscalar) :: phi1
    real(mytype), intent(in), dimension(xsize(1),xsize(2),xsize(3)) :: ep1
    integer, intent(in) :: num

    ! Write vorticity as an example of post processing

    ! Perform communications if needed
    if (sync_vel_needed) then
      call transpose_x_to_y(ux1,ux2)
      call transpose_x_to_y(uy1,uy2)
      call transpose_x_to_y(uz1,uz2)
      call transpose_y_to_z(ux2,ux3)
      call transpose_y_to_z(uy2,uy3)
      call transpose_y_to_z(uz2,uz3)
      sync_vel_needed = .false.
    endif

    !x-derivatives
    call derx (ta1,ux1,di1,sx,ffx,fsx,fwx,xsize(1),xsize(2),xsize(3),0,ubcx)
    call derx (tb1,uy1,di1,sx,ffxp,fsxp,fwxp,xsize(1),xsize(2),xsize(3),1,ubcy)
    call derx (tc1,uz1,di1,sx,ffxp,fsxp,fwxp,xsize(1),xsize(2),xsize(3),1,ubcz)
    !y-derivatives
    call dery (ta2,ux2,di2,sy,ffyp,fsyp,fwyp,ppy,ysize(1),ysize(2),ysize(3),1,ubcx)
    call dery (tb2,uy2,di2,sy,ffy,fsy,fwy,ppy,ysize(1),ysize(2),ysize(3),0,ubcy)
    call dery (tc2,uz2,di2,sy,ffyp,fsyp,fwyp,ppy,ysize(1),ysize(2),ysize(3),1,ubcz)
    !!z-derivatives
    call derz (ta3,ux3,di3,sz,ffzp,fszp,fwzp,zsize(1),zsize(2),zsize(3),1,ubcx)
    call derz (tb3,uy3,di3,sz,ffzp,fszp,fwzp,zsize(1),zsize(2),zsize(3),1,ubcy)
    call derz (tc3,uz3,di3,sz,ffz,fsz,fwz,zsize(1),zsize(2),zsize(3),0,ubcz)
    !!all back to x-pencils
    call transpose_z_to_y(ta3,td2)
    call transpose_z_to_y(tb3,te2)
    call transpose_z_to_y(tc3,tf2)
    call transpose_y_to_x(td2,tg1)
    call transpose_y_to_x(te2,th1)
    call transpose_y_to_x(tf2,ti1)
    call transpose_y_to_x(ta2,td1)
    call transpose_y_to_x(tb2,te1)
    call transpose_y_to_x(tc2,tf1)
    !du/dx=ta1 du/dy=td1 and du/dz=tg1
    !dv/dx=tb1 dv/dy=te1 and dv/dz=th1
    !dw/dx=tc1 dw/dy=tf1 and dw/dz=ti1

    !Q=-0.5*(ta1**2+te1**2+di1**2)-td1*tb1-tg1*tc1-th1*tf1
    di1 = zero
    di1(:,:,:) = - half*(ta1(:,:,:)**2 + te1(:,:,:)**2 + ti1(:,:,:)**2) &
                 - td1(:,:,:) * tb1(:,:,:) &
                 - tg1(:,:,:) * tc1(:,:,:) &
                 - th1(:,:,:) * tf1(:,:,:)
    call write_field(di1, ".", "critq", num, flush = .true.) ! Reusing temporary array, force flush

    if (mhd_active) then
      call write_field(Je(:,:,:,1), ".", "J_x", num, flush = .true.)
      call write_field(Je(:,:,:,2), ".", "J_y", num, flush = .true.)
      call write_field(Je(:,:,:,3), ".", "J_z", num, flush = .true.)
      call write_field(Bm(:,:,:,1), ".", "B_x", num, flush = .true.)
      call write_field(Bm(:,:,:,2), ".", "B_y", num, flush = .true.)
      call write_field(Bm(:,:,:,3), ".", "B_z", num, flush = .true.)
    endif
    
  end subroutine visu_rough
  !############################################################################
  !############################################################################
  !!
  !!  SUBROUTINE: momentum_forcing
  !!      AUTHOR: Paul Bartholomew
  !! DESCRIPTION: Applies rotation for t < spinup_time.
  !!
  !############################################################################
  subroutine momentum_forcing_rough(dux1, duy1, duz1, ux1, uy1, uz1)

    implicit none

    real(mytype), intent(in), dimension(xsize(1), xsize(2), xsize(3)) :: ux1, uy1, uz1
    real(mytype), dimension(xsize(1), xsize(2), xsize(3), ntime) :: dux1, duy1, duz1    

    if (cpg) then
        !! fcpg: add constant pressure gradient in streamwise direction
        if (idir_stream == 1) then
           dux1(:,:,:,1) = dux1(:,:,:,1) + fcpg !* (re/re_cent)**2
        else
           duz1(:,:,:,1) = duz1(:,:,:,1) + fcpg !* (re/re_cent)**2
        endif
    endif

    ! To update to take into account possible flow in z dir
    if (itime < spinup_time .and. iin <= 2) then
       if (nrank==0.and.(mod(itime, ilist) == 0 .or. itime == ifirst .or. itime == ilast)) &
          write(*,*) 'Rotating turbulent rough at speed ',wrotation
       dux1(:,:,:,1) = dux1(:,:,:,1) - wrotation*uy1(:,:,:)
       duy1(:,:,:,1) = duy1(:,:,:,1) + wrotation*ux1(:,:,:)
    endif
    
  end subroutine momentum_forcing_rough
  !############################################################################
  !############################################################################
  subroutine geomcomplex_rough(epsi,nxx,nxi,nxf,nyy,nyi,nyf,nzz,nzi,nzf,xxp,yyp,zzp,remp)

    use param, only : zero, one, two, three, ten, pi, yly, zlz
    use param, only : new_rec
    use ibm_param
    use complex_geometry, only : nraf

    implicit none

    integer                                         :: nxx,nxi,nxf,nyy,nyi,nyf,nzz,nzi,nzf
    real(mytype),dimension(nxi:nxf,nyi:nyf,nzi:nzf) :: epsi
    real(mytype),dimension(nxx)                     :: xxp
    real(mytype),dimension(nyy)                     :: yyp
    real(mytype),dimension(nzz)                     :: zzp
    real(mytype)                                    :: remp, tol
    real(mytype)                                    :: r,ym,zm,xm
    !LOCALS
    integer                                         :: i,j,k,irank,code,is
    integer                                         :: iprint
    !real(mytype),dimension(nz,nx,2) :: rmat  !here the dimension 2 contains BOTH walls. So you need to provide both roughness matrices    
    real(mytype)                                    :: hraf
     
    epsi(:,:,:) = zero
    tol = 1e-15
    ! #Rough map file readin --------------------------------------
    ! Use these dimensions when the map matches the grid resolution
    !nrows = nz
    !ncols = nx
    
    !New Reconstruction (through transverse-yz directions periodicity)?---------
    new_rec=0   ! 0: standard | 1: new reconstruction ---> Check ibm.f90 lagpoly2(u) !!!
    !---------------------------------------------------------------------------

    !====DEBUG
    iprint=0
    !if (nxx.eq.nx) iprint=1
    !if (nxx.gt.nx) iprint=1
    !if (nzz.gt.nz) iprint=1

    !Epsilon matrix
    do k=nzi,nzf
        zm=zzp(k)

        do j=nyi,nyf
            ym=yyp(j)

            do i=nxi,nxf
                xm=xxp(i)
		
		!if (nraf.eq.1) then
		  
		   ! WITHOUT NRAF FUNCTIONALITY
                   ! if ((ym.lt.(rmat(k,i,1))).or.(ym.gt.(yly-rmat(k,i,1)))) then
                   !     epsi(i,j,k)=remp
                   ! endif		  
		!else
                    !if (nrank==0..and.iprint==1) print*,'HERE1',i,j,k
                    hraf = interp_hraf(i,j,k,xxp,yyp,zzp,nxx,nyy,nzz,iprint)
                    !if (nrank==0..and.iprint==1) print*,'HERE2',i,j,k
                
                    if (ym.lt.yly/two.and.ym.lt.hraf) then
                       epsi(i,j,k) = remp
	            elseif (ym.lt.yly/two.and.abs(ym-hraf).lt.tol) then
	               epsi(i,j,k) = remp
                    elseif (ym.gt.yly/two.and.ym.gt.(yly-hraf)) then
                       epsi(i,j,k) = remp
		    elseif (ym.gt.yly/two.and.abs(ym-(yly-hraf)).lt.tol) then
	               epsi(i,j,k) = remp
                    endif
                  
                !endif
                !====DEBUG
                if (iprint.eq.1) then
                    do irank=-100*nrank,100
                        !if (nrank.eq.0) then
                        if (irank.eq.nrank) then
                        !if (k.eq.nz/2+1) then
                            !print*, 'eps=', yyp(j), xxp(i), epsi(i,j,k)
                            print*, 'eps=', xxp(i), yyp(j), zzp(k), epsi(i,j,k)
                        endif
                        !endif
                        !!!$if (i.eq.nx/2+1) then
                        !    !!$print*, 'eps=', yyp(j), zzp(k), epsi(i,j,k)
                        !    print*, 'eps=', xxp(i), yyp(j), zzp(k), epsi(i,j,k)
                        !!!$endif
                    enddo
                endif
            enddo
        enddo
    enddo
    return
  end subroutine geomcomplex_rough
  !############################################################################
  !############################################################################
  subroutine read_roughness(nrows,ncols)
 
    use param
    use ibm_param, only : surfacefile, rmat

    implicit none

    integer                         :: nrows,ncols
    !real(mytype),dimension(nz,nx,2) :: rmat !here the dimension 2 contains BOTH walls. So you need to provide both roughness matrices
    character(len=100)              :: filename 
    integer :: i,j, io_status
    
    !rmat = zero
    filename = surfacefile    
 
     ! Read the filename and dimensions from the namelist
     print *, 'Check 0: found correct filename: ', trim(filename)
     print *, 'Matrix dimensions: ',nrows,'x',ncols
  
     ! Open the file
     open(unit=33, file=filename, status='old', action='read', iostat=io_status)
     if (io_status /= 0) then
        print *, 'Error opening file ', trim(filename)
     stop
     endif
     print *, 'Check 1: File opened successfully'
  
    ! Read the matrix data from the file
    do i = 1, nrows
      read(33, *, iostat=io_status) (rmat(i, j, 1), j = 1, ncols)
      !read(33, *, iostat=io_status) (rmat(i, j, 2), j = 1, ncols)        
      if (io_status /= 0) then
         print *, 'Error reading matrix data from file ', trim(filename)
         close(33)
         stop
      endif
    enddo
    close(33)
    print *, 'Check 3: Matrix data read successfully'
     
    rmat(:,:,2) = rmat(:,:,1)
     
     
    !!$!====DEBUG
    !if (nrank.eq.2) then
    !    do k=1,nz
    !        do i=1,nx
    !            print*, k, i, real(rmat(i,k,1),4), real(rmat(i,k,2),4)
    !        enddo
    !    enddo
    !endif
    !call sleep(10)
    !stop
    return
  end subroutine read_roughness

  !############################################################################
  !############################################################################
  function interp_hraf(i,j,k,xxp,yyp,zzp,nxx,nyy,nzz,iprint)

    use variables, only : xp,yp,zp
    use ibm_param
    use param    , only : yly,two

    implicit none

    real(mytype)                :: interp_hraf
    !real(mytype),dimension(nz,nx,2) :: rmat
    integer                     :: nxx,nyy,nzz
    real(mytype),dimension(nxx) :: xxp
    real(mytype),dimension(nyy) :: yyp
    real(mytype),dimension(nzz) :: zzp
    integer                     :: i,j,k
    !LOCALS
    real(mytype)      :: x1,x2,y1,y2
    integer,parameter :: nrel=10 !relaxation factor
    integer           :: rafdir,ii,jj,kk,jside,&
                         imin,imax,kmin,kmax
    integer           :: iprint

    !Refined direction?
    rafdir=0                      !(nx   ,ny   ,nz   )
    if (nxx.gt.nx) rafdir=1       !(nxraf,ny   ,nz   )
    if (nyy.gt.ny) rafdir=2       !(nx   ,nyraf,nz   )
    if (nzz.gt.nz) rafdir=3       !(nx   ,ny   ,nzraf)
    !====DEBUG
    if (nrank.eq.0.and.iprint.eq.1) print*, 'rafdir=', rafdir

    !Lower or upper wall?
    if (yyp(j).lt.yly/two) then
        jside=1
    else
        jside=2
    endif

    if (rafdir.eq.1) then !if refined in x-direction

        !get interpolation data
        if (xxp(i).lt.xp(nx)) then !internal grid point?
            !local safety range to track index
            imin=max(1 , (nint(xxp(i)/dx)+1)-nrel)
            imax=min(nx, (nint(xxp(i)/dx)+1)+nrel)
            do ii=imin,imax
                if (xxp(i).ge.xp(ii).and.xxp(i).lt.xp(ii+1)) exit !get local index from mesh grid
            enddo
            !
            y1=rmat(k,ii,  jside)
            y2=rmat(k,ii+1,jside)
            x1=xp(ii  )
            x2=xp(ii+1)
        else !interpolation across domain periodicity
            y1=rmat(k,nx,jside)
            y2=rmat(k,1 ,jside)
            x1=xp(nx)
            x2=xp(nx)+dx
        endif

        !linear interpolation
        interp_hraf = ((y2-y1)/(x2-x1))*(xxp(i)-x1)+y1

    elseif (rafdir.eq.3) then !if refined in z-direction

        !get interpolation data
        if (zzp(k).lt.zp(nz)) then !internal grid point?
            !local safety range to track index
            kmin=max(1 , (nint(zzp(k)/dz)+1)-nrel)
            kmax=min(nz, (nint(zzp(k)/dz)+1)+nrel)
            do kk=kmin,kmax
                if (zzp(k).ge.zp(kk).and.zzp(k).lt.zp(kk+1)) exit !get local index from mesh grid
            enddo
            !
            y1=rmat(kk,  i,jside)
            y2=rmat(kk+1,i,jside)
            !
            x1=zp(kk  )
            x2=zp(kk+1)
        else !interpolation across domain periodicity
            y1=rmat(nz,i,jside)
            y2=rmat(1 ,i,jside)
            !
            x1=zp(nz)
            x2=zp(nz)+dz
        endif

        !linear interpolation
        interp_hraf = ((y2-y1)/(x2-x1))*(zzp(k)-x1)+y1 !linear interpolation
    else
        interp_hraf = rmat(k,i,jside) !no interpolation needed
    endif
    !
    return
            
  end function interp_hraf
  !############################################################################
  !############################################################################
  subroutine sem_init_rough(ux1, uy1, uz1)

    implicit none

    ! Arguments
    real(mytype),dimension(xsize(1),xsize(2),xsize(3)) :: ux1,uy1,uz1

    ! Local variables
    integer :: i, j, k, ii, jj
    real(mytype) :: x, y, z, ftent, um
    integer ( kind = 4 ), parameter :: nsemini = 1000 ! For the moment we fix it but after this can go in the input file
    real(mytype), dimension(3,nsemini) :: eddy, posvor
    real(mytype)     :: volsemini, rrand, ddx, ddy, ddz, lsem, upr, vpr, wpr
    real(mytype), dimension(3) :: dim_min, dim_max

     dim_min(1) = zero
     dim_min(2) = zero
     dim_min(3) = zero
     dim_max(1) = xlx
     dim_max(2) = yly
     dim_max(3) = zlz
     volsemini = xlx * yly * zlz
     ! 3 int to get different random numbers
     do jj = 1, nsemini
        ! Vortex Position
        do ii = 1, 3
           call random_number(rrand)
           posvor(ii,jj) = dim_min(ii)+(dim_max(ii)-dim_min(ii))*rrand
        enddo
        ! Eddy intensity
        do ii = 1, 3
           call random_number(rrand)
           if (rrand <= zpfive) then
              eddy(ii,jj) = -one
           else
              eddy(ii,jj) = +one
           endif 
        enddo
     enddo
     ! Loops to apply the fluctuations 
     do k = 1, xsize(3)
        z = real((k+xstart(3)-1-1),mytype)*dz
        do j = 1, xsize(2)
           if (istret==0) y=real(j+xstart(2)-2,mytype)*dy
           if (istret/=0) y=yp(j+xstart(2)-1)
           do i = 1, xsize(1)
              x = real(i-1,mytype)*dx
              lsem = 0.15_mytype ! For the moment we keep it constant
              upr = zero
              vpr = zero
              wpr = zero
              do jj = 1, nsemini
                 ddx = abs(x-posvor(1,jj))
                 ddy = abs(y-posvor(2,jj))
                 ddz = abs(z-posvor(3,jj))
                 if (ddx < lsem .and. ddy < lsem .and. ddz < lsem) then
                    ! coefficients for the intensity of the fluctuation
                    ftent = (one-ddx/lsem)*(one-ddy/lsem)*(one-ddz/lsem)
                    ftent = ftent / (sqrt(two/three*lsem))**3
                    upr = upr + eddy(1,jj) * ftent
                    vpr = vpr + eddy(2,jj) * ftent
                    wpr = wpr + eddy(3,jj) * ftent
                 endif
              enddo
              upr = upr * sqrt(volsemini/nsemini)
              vpr = vpr * sqrt(volsemini/nsemini)
              wpr = wpr * sqrt(volsemini/nsemini)
              ! 
              um  = one-(y-yly*half)**2 ! we can use a better arroximation 
              if (idir_stream == 1) then
                 ux1(i,j,k)=upr*sqrt(two/three*init_noise*um) + um
                 uy1(i,j,k)=vpr*sqrt(two/three*init_noise*um)
                 uz1(i,j,k)=wpr*sqrt(two/three*init_noise*um)
              else
                 uz1(i,j,k)=upr*sqrt(two/three*init_noise*um) + um
                 uy1(i,j,k)=vpr*sqrt(two/three*init_noise*um)
                 ux1(i,j,k)=wpr*sqrt(two/three*init_noise*um)
              endif
           enddo
        enddo
     enddo

  end subroutine sem_init_rough
  !############################################################################
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!
    !!  SUBROUTINE: axial_averaging
    !!      AUTHOR: Rodrigo Vicente Cruz
    !! DESCRIPTION: Performs axial averaging (streamwise-x direction)
    !!
  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  !***************************************************************************
  !
  subroutine axial_averaging(var)
  !
  !***************************************************************************
  USE param
  USE variables
  USE decomp_2d
  USE MPI
  USE ibm
  !
  implicit none
  real(mytype),dimension(xsize(1),xsize(2),xsize(3))    :: var
  !LOCALS
  real(mytype),dimension(xsize(2),xsize(3))             :: varm
  integer                                               :: i,j,k
  !

  varm(:,:)=zero
  do k=1,xsize(3)
      do j=1,xsize(2)
          do i=1,xsize(1)
              varm(j,k) = varm(j,k) + var(i,j,k)
          enddo
      enddo
  enddo
  varm(:,:) = varm(:,:)/dble(xsize(1))
  do k=1,xsize(3)
      do j=1,xsize(2)
          do i=1,xsize(1)
              var(i,j,k) = varm(j,k)
          enddo
      enddo
  enddo
  !
  return
  end subroutine axial_averaging
end module rough
