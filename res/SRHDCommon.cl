#include "HydroGPU/Shared/Common.h"

//velocity
#if DIM == 1
#define VELOCITY(ptr)	((real4)((ptr)[PRIMITIVE_VELOCITY_X], 0., 0., 0.))
#elif DIM == 2
#define VELOCITY(ptr)	((real4)((ptr)[PRIMITIVE_VELOCITY_X], (ptr)[PRIMITIVE_VELOCITY_Y], 0., 0.))
#elif DIM == 3
#define VELOCITY(ptr)	((real4)((ptr)[PRIMITIVE_VELOCITY_X], (ptr)[PRIMITIVE_VELOCITY_Y], (ptr)[PRIMITIVE_VELOCITY_Z], 0.))
#endif

/*
Incoming is Newtonian Euler equation state variables: density, momentum, newtonian total energy density
Outgoing is the SRHD primitives associated with it: density, velocity?, and pressure
		and the SRHD state variables:
*/
__kernel void initVariables(
	__global real* stateBuffer,
	__global real* primitiveBuffer)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	int index = INDEXV(i);

	__global real* state = stateBuffer + NUM_STATES * index;
	__global real* primitive = primitiveBuffer + NUM_STATES * index;
/*
special modification for SRHD
 until I put more thought into the issue of unifying all iniital state variables for all solvers
I could go back to labelling initial states
then change the problems to provide either internal specific energy or newtonian pressure
and change the solvers C++ code to apply these transformations...
or I could just provide separate initial states for all Euler/MDH and all SRHD equations ...
or I could provide a wrapper like this ...

I usually write out variable names in this project,
but for SRHD we have variables like rho = "rest-mass density" and D = "rest-mass density from Eulerian frame"
... sooo ... 
watch me for the changes
and try to keep up
*/
	// calculate newtonian primitives from state vector
	real rho = state[0];
	real4 v = (real4)(0., 0., 0., 0.);
	v.x = state[1] / state[0];
#if DIM > 1
	v.y = state[2] / state[0];
#if DIM > 2
	v.z = state[3] / state[0];
#endif
#endif
	real ETotalClassic = state[DIM+1];
	real vSq = dot(v, v);	
	real eKinClassic = .5 * vSq;
	real eTotalClassic = ETotalClassic / rho;
	real eInt = eTotalClassic - eKinClassic;
	// recast them as SR state variables 
	real P = (gamma - 1.) * rho * eInt;
	real h = 1. + eInt + P / rho; 
	real WSq = 1. / (1. - vSq);
	real W = sqrt(WSq);
	real D = rho * W;
	real4 S = rho * h * WSq * v;
	real tau = rho * h * WSq - P - D;
	//write primitives
	primitive[PRIMITIVE_DENSITY] = rho;
	primitive[PRIMITIVE_VELOCITY_X] = v.x;
#if DIM > 1
	primitive[PRIMITIVE_VELOCITY_Y] = v.y;
#if DIM > 2
	primitive[PRIMITIVE_VELOCITY_Z] = v.z;
#endif
#endif
	primitive[PRIMITIVE_SPECIFIC_INTERNAL_ENERGY] = eInt;
	//write conservatives
	state[STATE_REST_MASS_DENSITY] = D;
	state[STATE_MOMENTUM_DENSITY_X] = S.x;
#if DIM > 1
	state[STATE_MOMENTUM_DENSITY_Y] = S.y;
#if DIM > 2
	state[STATE_MOMENTUM_DENSITY_Z] = S.z;
#endif
#endif
	state[STATE_TOTAL_ENERGY_DENSITY] = tau;
}

// convert conservative to primitive using root-finding
//From Marti & Muller 2008
__kernel void updatePrimitives(
	__global real* primitiveBuffer,
	const __global real* stateBuffer)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	int index = INDEXV(i);

	const __global real* state = stateBuffer + NUM_STATES * index;
	real D = state[STATE_REST_MASS_DENSITY];
#if DIM == 1
	real4 S = (real4)(state[STATE_MOMENTUM_DENSITY_X], 0., 0., 0.);
#elif DIM == 2
	real4 S = (real4)(state[STATE_MOMENTUM_DENSITY_X], state[STATE_MOMENTUM_DENSITY_Y], 0., 0.);
#elif DIM == 3
	real4 S = (real4)(state[STATE_MOMENTUM_DENSITY_X], state[STATE_MOMENTUM_DENSITY_Y], state[STATE_MOMENTUM_DENSITY_Z], 0.);
#endif
	real tau = state[STATE_TOTAL_ENERGY_DENSITY];

	__global real* primitive = primitiveBuffer + NUM_STATES * index;
	//real rho = primitive[PRIMITIVE_DENSITY];
#if DIM == 1
	real4 v = (real4)(primitive[PRIMITIVE_VELOCITY_X], 0., 0., 0.);
#elif DIM == 2
	real4 v = (real4)(primitive[PRIMITIVE_VELOCITY_X], primitive[PRIMITIVE_VELOCITY_Y], 0., 0.);
#elif DIM == 3
	real4 v = (real4)(primitive[PRIMITIVE_VELOCITY_X], primitive[PRIMITIVE_VELOCITY_Y], primitive[PRIMITIVE_VELOCITY_Z], 0.);
#endif
	//real eInt = primitive[PRIMITIVE_SPECIFIC_INTERNAL_ENERGY];

	D = max(D, 1e-10);
	tau = max(tau, 1e-10);

	real SLen = length(S);
	const real velocityEpsilon = 1e-16;
	real PMin = max(SLen - tau - D + SLen * velocityEpsilon, 1e-16);
	real PMax = (gamma - 1.) * tau;
	PMax = max(PMax, PMin);
	real P = .5 * (PMin + PMax);

#define PRESSURE_MAX_ITERATIONS 100
	for (int iter = 0; iter < PRESSURE_MAX_ITERATIONS; ++iter) {
		real vLen = SLen / (tau + D + P);
		real vSq = vLen * vLen;
		real W = 1. / sqrt(1. - vSq);
		real eInt = (tau + D * (1. - W) + P * (1. - W*W)) / (D * W);
		real rho = D / W;
		real f = (gamma - 1.) * rho * eInt - P;
		real csSq = (gamma - 1.) * (tau + D * (1. - W) + P) / (tau + D + P);
		real df_dP = vSq * csSq - 1.;
		real newP = P - f / df_dP;
		newP = max(newP, PMin);
		real PError = fabs(1. - newP / P);
		P = newP;
#define SOLVE_PRIM_STOP_EPSILON	1e-7
		if (PError < SOLVE_PRIM_STOP_EPSILON) {
			v = S * (1. / (tau + D + P));
			W = 1. / sqrt(1. - dot(v,v));
			rho = D / W;
			eInt = P / (rho * (gamma - 1.));
			primitive[PRIMITIVE_DENSITY] = rho;
			primitive[PRIMITIVE_VELOCITY_X] = v.x;
#if DIM > 1
			primitive[PRIMITIVE_VELOCITY_Y] = v.y;
#if DIM > 2
			primitive[PRIMITIVE_VELOCITY_Z] = v.z;
#endif
#endif
			primitive[PRIMITIVE_SPECIFIC_INTERNAL_ENERGY] = eInt;
			break;
		}
	}
}

//specific to Euler equations
__kernel void convertToTex(
	__write_only image3d_t destTex,
	int displayMethod,
	const __global real* primitiveBuffer)
//const __global real* potentialBuffer		
//TODO get SRHD equation working with selfgrav by renaming STATE_REST_MASS_DENSITY to STATE_DENSITY
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	int index = INDEXV(i);

	const __global real* primitive = primitiveBuffer + NUM_STATES * index;

	real rho = primitive[PRIMITIVE_DENSITY];
	real vSq = primitive[PRIMITIVE_VELOCITY_X] * primitive[PRIMITIVE_VELOCITY_X];
#if DIM > 1
	vSq += primitive[PRIMITIVE_VELOCITY_Y] * primitive[PRIMITIVE_VELOCITY_Y];
#endif
#if DIM > 2
	vSq += primitive[PRIMITIVE_VELOCITY_Z] * primitive[PRIMITIVE_VELOCITY_Z];
#endif
	real vLen = sqrt(vSq);
	real eInt = primitive[PRIMITIVE_SPECIFIC_INTERNAL_ENERGY];
	real P = (gamma - 1.) * rho * eInt;

	real value;
	switch (displayMethod) {
	case DISPLAY_DENSITY:	//density
		value = rho;
		break;
	case DISPLAY_VELOCITY:	//velocity
		value = vLen;
		break;
	case DISPLAY_PRESSURE:	//pressure
		value = P;
		break;
	case DISPLAY_POTENTIAL:
		value = 0.;//potentialBuffer[index];	//TODO get SRHD equation working with selfgrav by renaming STATE_REST_MASS_DENSITY to STATE_DENSITY
		break;
	default:
		value = .5;
		break;
	}

	write_imagef(destTex, (int4)(i.x, i.y, i.z, 0), (float4)(value, 0., 0., 0.));
}

constant float2 offset[6] = {
	(float2)(-.5, 0.),
	(float2)(.5, 0.),
	(float2)(.2, .3),
	(float2)(.5, 0.),
	(float2)(.2, -.3),
	(float2)(.5, 0.),
};

__kernel void updateVectorField(
	__global float* vectorFieldVertexBuffer,
	const __global real* stateBuffer,
	real scale)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	int4 size = (int4)(get_global_size(0), get_global_size(1), get_global_size(2), 0);	
	int vertexIndex = i.x + size.x * (i.y + size.y * i.z);
	__global float* vertex = vectorFieldVertexBuffer + 6 * 3 * vertexIndex;
	
	float4 f = (float4)(
		((float)i.x + .5) / (float)size.x,
		((float)i.y + .5) / (float)size.y,
		((float)i.z + .5) / (float)size.z,
		0.);

	//times grid size divided by velocity field size
	float4 sf = (float4)(f.x * SIZE_X, f.y * SIZE_Y, f.z * SIZE_Z, 0.);
	int4 si = (int4)(sf.x, sf.y, sf.z, 0);
	//float4 fp = (float4)(sf.x - (float)si.x, sf.y - (float)si.y, sf.z - (float)si.z, 0.);
	
#if 1	//plotting velocity 
	//TODO this isn't correct velocity! use the primitive buffer!
	int stateIndex = INDEXV(si);
	const __global real* state = stateBuffer + NUM_STATES * stateIndex;
	real4 velocity = VELOCITY(state);
#endif
#if 0	//plotting gravity
	int4 ixL = si; ixL.x = (ixL.x + SIZE_X - 1) % SIZE_X;
	int4 ixR = si; ixR.x = (ixR.x + 1) % SIZE_X;
	int4 iyL = si; iyL.y = (iyL.y + SIZE_X - 1) % SIZE_X;
	int4 iyR = si; iyR.y = (iyR.y + 1) % SIZE_X;
	//external force is negative the potential gradient
	real4 velocity = (float4)(
		gravityPotentialBuffer[INDEXV(ixL)] - gravityPotentialBuffer[INDEXV(ixR)],
		gravityPotentialBuffer[INDEXV(iyL)] - gravityPotentialBuffer[INDEXV(iyR)],
		0.,
		0.);
#endif

	//velocity is the first axis of the basis to draw the arrows
	//the second should be perpendicular to velocity
#if DIM < 3
	real4 tv = (real4)(-velocity.y, velocity.x, 0., 0.);
#elif DIM == 3
	real4 vx = (real4)(0., -velocity.z, velocity.y, 0.);
	real4 vy = (real4)(velocity.z, 0., -velocity.x, 0.);
	real4 vz = (real4)(-velocity.y, velocity.x, 0., 0.);
	real lxsq = dot(vx,vx);
	real lysq = dot(vy,vy);
	real lzsq = dot(vz,vz);
	real4 tv;
	if (lxsq > lysq) {	//x > y
		if (lxsq > lzsq) {	//x > z, x > y
			tv = vx;
		} else {	//z > x > y
			tv = vz;
		}
	} else {	//y >= x
		if (lysq > lzsq) {	//y >= x, y > z
			tv = vy;
		} else {	// z > y >= x
			tv = vz;
		}
	}
#endif

	for (int i = 0; i < 6; ++i) {
		vertex[0 + 3 * i] = f.x * (XMAX - XMIN) + XMIN + scale * (offset[i].x * velocity.x + offset[i].y * tv.x);
		vertex[1 + 3 * i] = f.y * (YMAX - YMIN) + YMIN + scale * (offset[i].x * velocity.y + offset[i].y * tv.y);
		vertex[2 + 3 * i] = f.z * (ZMAX - ZMIN) + ZMIN + scale * (offset[i].x * velocity.z + offset[i].y * tv.z);
	}
}

__kernel void poissonRelax(
	__global real* potentialBuffer,
	const __global real* stateBuffer,
	int4 repeat)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	int index = INDEXV(i);

	real sum = 0.;
	for (int side = 0; side < DIM; ++side) {
		int4 iprev = i;
		int4 inext = i;
		if (repeat[side]) {
			iprev[side] = (iprev[side] + size[side] - 1) % size[side];
			inext[side] = (inext[side] + 1) % size[side];
		} else {
			iprev[side] = max(iprev[side] - 1, 0);
			inext[side] = min(inext[side] + 1, size[side] - 1);
		}
		int indexPrev = INDEXV(iprev);
		int indexNext = INDEXV(inext);
		sum += potentialBuffer[indexPrev] + potentialBuffer[indexNext];
	}
	
	real scale = M_PI * GRAVITATIONAL_CONSTANT * DX;
#if DIM > 1
	scale *= DY; 
#endif
#if DIM > 2
	scale *= DZ; 
#endif
	real density = stateBuffer[STATE_REST_MASS_DENSITY + NUM_STATES * index];
	potentialBuffer[index] = sum / (2. * (float)DIM) + scale * density;
}

__kernel void calcGravityDeriv(
	__global real* derivBuffer,
	const __global real* stateBuffer,
	const __global real* gravityPotentialBuffer)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	if (i.x < 2 || i.x >= SIZE_X - 2
#if DIM > 1
		|| i.y < 2 || i.y >= SIZE_Y - 2
#endif
#if DIM > 2
		|| i.z < 2 || i.z >= SIZE_Z - 2
#endif
	) {
		return;
	}
	int index = INDEXV(i);

	__global real* deriv = derivBuffer + NUM_STATES * index;
	const __global real* state = stateBuffer + NUM_STATES * index;

	for (int j = 0; j < NUM_STATES; ++j) {
		deriv[j] = 0.;
	}

	real density = state[STATE_REST_MASS_DENSITY];

	for (int side = 0; side < DIM; ++side) {
		int indexPrev = index - stepsize[side];
		int indexNext = index + stepsize[side];
	
		real gravityPotentialGradient = .5 * (gravityPotentialBuffer[indexNext] - gravityPotentialBuffer[indexPrev]);
	
		//gravitational force = -gradient of gravitational potential
		deriv[side + STATE_MOMENTUM_DENSITY_X] -= density * gravityPotentialGradient / dx[side];
		deriv[STATE_TOTAL_ENERGY_DENSITY] -= density * gravityPotentialGradient * state[side + STATE_MOMENTUM_DENSITY_X];
	}
}
