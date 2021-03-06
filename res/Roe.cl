#include "HydroGPU/Shared/Common.h"
#include "HydroGPU/Roe.h"

__kernel void calcCellTimestep(
	__global real* dtBuffer,
//Hydrodynamics ii
#if 1
	const __global real* eigenvaluesBuffer
#endif
//Toro 16.38
#if 0
	const __global real* stateBuffer
#endif
#ifdef SOLID
	, const __global char* solidBuffer
#endif	//SOLID
)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	int index = INDEXV(i);

	if (i.x < 2 || i.x >= SIZE_X - 2 
#if DIM > 1
		|| i.y < 2 || i.y >= SIZE_Y - 2
#endif
#if DIM > 2
		|| i.z < 2 || i.z >= SIZE_Z - 2
#endif
	) {
		for (int side = 0; side < DIM; ++side) {
			dtBuffer[side + DIM * index] = INFINITY;
		}
		return;
	}
	
	for (int side = 0; side < DIM; ++side) {
		int indexL = index;
		int indexR = index + stepsize[side];

#ifdef SOLID
		if (solidBuffer[indexL] || solidBuffer[indexR]) {
			dtBuffer[side + DIM * index] = INFINITY; 
			continue;
		}
#endif	//SOLID

		const __global real* eigenvaluesL = eigenvaluesBuffer + EIGEN_SPACE_DIM * (side + DIM * indexL);
		const __global real* eigenvaluesR = eigenvaluesBuffer + EIGEN_SPACE_DIM * (side + DIM * indexR);
		
		//NOTICE assumes eigenvalues are sorted from min to max
		real maxLambda = (real)max((real)0., eigenvaluesL[EIGEN_SPACE_DIM-1]);
		real minLambda = (real)min((real)0., eigenvaluesR[0]);
		
//Hydrodynamics ii
#if 1
		real dum = dx[side] / (fabs(maxLambda - minLambda) + 1e-9);
#endif
//Toro 16.38
#if 0
		real dum = dx[side] / ((real)max((real)fabs(minLambda), (real)fabs(maxLambda)) + (real)1e-9);
#endif
		
		dtBuffer[side + DIM * index] = dum;
	}
}

void calcDeltaQTildeSide(
	__global real* deltaQTildeBuffer,
	const __global real* eigenvectorsBuffer,
	const __global real* stateBuffer,
	int side
#ifdef SOLID
	, const __global char* solidBuffer
#endif	//SOLID
);

void calcDeltaQTildeSide(
	__global real* deltaQTildeBuffer,
	const __global real* eigenvectorsBuffer,
	const __global real* stateBuffer,
	int side
#ifdef SOLID
	, const __global char* solidBuffer
#endif	//SOLID
)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	if (i.x < 2 || i.x >= SIZE_X - 1 
#if DIM > 1
		|| i.y < 2 || i.y >= SIZE_Y - 1
#endif
#if DIM > 2
		|| i.z < 2 || i.z >= SIZE_Z - 1
#endif
	) return;
	
	int index = INDEXV(i);
	int indexPrev = index - stepsize[side];
	int interfaceIndex = side + DIM * index;
	
	const __global real* eigenvectors = eigenvectorsBuffer + EIGEN_TRANSFORM_STRUCT_SIZE * interfaceIndex;
	__global real* deltaQTilde = deltaQTildeBuffer + EIGEN_SPACE_DIM * interfaceIndex;
	
	real stateL[NUM_STATES];
	real stateR[NUM_STATES];
	for (int i = 0; i < NUM_STATES; ++i) {
		stateL[i] = stateBuffer[i + NUM_STATES * indexPrev];
		stateR[i] = stateBuffer[i + NUM_STATES * index];
	}
#ifdef SOLID
	char solidL = solidBuffer[indexPrev];
	char solidR = solidBuffer[index];
	if (solidL && !solidR) {
		for (int i = 0; i < NUM_STATES; ++i) {
			stateL[i] = stateR[i];
		}
		stateL[side+STATE_MOMENTUM_X] = -stateL[side+STATE_MOMENTUM_X];
	} else if (solidR && !solidL) {
		for (int i = 0; i < NUM_STATES; ++i) {
			stateR[i] = stateL[i];
		}
		stateR[side+STATE_MOMENTUM_X] = -stateR[side+STATE_MOMENTUM_X];
	}
#endif	//SOLID

#ifdef ROE_EIGENFIELD_TRANSFORM_SEPARATE
	//calculating this twice because leftEigenvectorTransform could use the state variables to construct the field information on the fly
	//...but would it be the correct state information?

	real stateLTilde[EIGEN_SPACE_DIM];
	leftEigenvectorTransform(stateLTilde, eigenvectors, stateL, side);

	real stateRTilde[EIGEN_SPACE_DIM];
	leftEigenvectorTransform(stateRTilde, eigenvectors, stateR, side);

	for (int i = 0; i < EIGEN_SPACE_DIM; ++i) {
		deltaQTilde[i] = stateRTilde[i] - stateLTilde[i];
	}
#else	//ROE_EIGENFIELD_TRANSFORM_SEPARATE
	real deltaState[NUM_STATES];
	real deltaQTilde_[EIGEN_SPACE_DIM];
	for (int i = 0; i < NUM_STATES; ++i) {
		deltaState[i] = stateR[i] - stateL[i];
	}
	leftEigenvectorTransform(deltaQTilde_, eigenvectors, deltaState, side);
	for (int i = 0; i < EIGEN_SPACE_DIM; ++i) {
		deltaQTilde[i] = deltaQTilde_[i];
	}
#endif	//ROE_EIGENFIELD_TRANSFORM_SEPARATE
}

__kernel void calcDeltaQTilde(
	__global real* deltaQTildeBuffer,
	const __global real* eigenvectorsBuffer,
	const __global real* stateBuffer
#ifdef SOLID
	, const __global char* solidBuffer
#endif	//SOLID
)
{
	for (int side = 0; side < DIM; ++side) {
		calcDeltaQTildeSide(deltaQTildeBuffer, eigenvectorsBuffer, stateBuffer, side
#ifdef SOLID
			, solidBuffer
#endif
		);
	}
}

void calcFluxSide(
	__global real* fluxBuffer,
	const __global real* stateBuffer,
	const __global real* eigenvaluesBuffer,
	const __global real* eigenvectorsBuffer,
	const __global real* deltaQTildeBuffer,
	real dt,
	int side
#ifdef SOLID
	, const __global char* solidBuffer
#endif	//SOLID
);

void calcFluxSide(
	__global real* fluxBuffer,
	const __global real* stateBuffer,
	const __global real* eigenvaluesBuffer,
	const __global real* eigenvectorsBuffer,
	const __global real* deltaQTildeBuffer,
	real dt,
	int side
#ifdef SOLID
	, const __global char* solidBuffer
#endif	//SOLID
)
{
	int4 i = (int4)(get_global_id(0), get_global_id(1), get_global_id(2), 0);
	if (i.x < 2 || i.x >= SIZE_X - 1 
#if DIM > 1
		|| i.y < 2 || i.y >= SIZE_Y - 1
#endif
#if DIM > 2
		|| i.z < 2 || i.z >= SIZE_Z - 1
#endif
	) return;
	
	real dt_dx = dt / dx[side];

	int index = INDEXV(i);
	int indexR = index;	
	
	int indexL = index - stepsize[side];
	int indexR2 = indexR + stepsize[side];

	int interfaceLIndex = side + DIM * indexL;
	int interfaceIndex = side + DIM * indexR;
	int interfaceRIndex = side + DIM * indexR2;
	
	const __global real* deltaQTildeL = deltaQTildeBuffer + EIGEN_SPACE_DIM * interfaceLIndex;
	const __global real* deltaQTilde = deltaQTildeBuffer + EIGEN_SPACE_DIM * interfaceIndex;
	const __global real* deltaQTildeR = deltaQTildeBuffer + EIGEN_SPACE_DIM * interfaceRIndex;
	
	const __global real* eigenvalues = eigenvaluesBuffer + EIGEN_SPACE_DIM * interfaceIndex;
	const __global real* eigenvectors = eigenvectorsBuffer + EIGEN_TRANSFORM_STRUCT_SIZE * interfaceIndex;
	__global real* flux = fluxBuffer + NUM_FLUX_STATES * interfaceIndex;

	real stateL[NUM_STATES];
	for (int i = 0; i < NUM_STATES; ++i) {
		stateL[i] = stateBuffer[i + NUM_STATES * indexL];
	}
	real stateR[NUM_STATES];
	for (int i = 0; i < NUM_STATES; ++i) {
		stateR[i] = stateBuffer[i + NUM_STATES * indexR];
	}
#ifdef SOLID
	int indexL2 = indexL - stepsize[side];
	char solidL = solidBuffer[indexL];
	char solidR = solidBuffer[indexR];
	if (solidL && !solidR) {
		for (int i = 0; i < NUM_STATES; ++i) {
			stateL[i] = stateR[i];
		}
		stateL[side+STATE_MOMENTUM_X] = -stateL[side+STATE_MOMENTUM_X];
	} else if (solidR && !solidL) {
		for (int i = 0; i < NUM_STATES; ++i) {
			stateR[i] = stateL[i];
		}
		stateR[side+STATE_MOMENTUM_X] = -stateR[side+STATE_MOMENTUM_X];
	}
	char solidL2 = solidBuffer[indexL2];
	char solidR2 = solidBuffer[indexR2];
#endif	//SOLID

	real fluxTilde[EIGEN_SPACE_DIM];
#ifdef ROE_EIGENFIELD_TRANSFORM_SEPARATE
	real stateLTilde[EIGEN_SPACE_DIM];
	leftEigenvectorTransform(stateLTilde, eigenvectors, stateL, side);

	real stateRTilde[EIGEN_SPACE_DIM];
	leftEigenvectorTransform(stateRTilde, eigenvectors, stateR, side);

	for (int i = 0; i < EIGEN_SPACE_DIM; ++i) {
		fluxTilde[i] = .5 * (stateRTilde[i] + stateLTilde[i]);
	}
#else	//ROE_EIGENFIELD_TRANSFORM_SEPARATE
	real stateAvg[NUM_STATES];
	for (int i = 0; i < NUM_STATES; ++i) {
		stateAvg[i] = .5 * (stateR[i] + stateL[i]);
	}
	leftEigenvectorTransform(fluxTilde, eigenvectors, stateAvg, side);
#endif	//ROE_EIGENFIELD_TRANSFORM_SEPARATE

	for (int i = 0; i < EIGEN_SPACE_DIM; ++i) {
		real eigenvalue = eigenvalues[i];
		fluxTilde[i] *= eigenvalue;

		real rTilde;
		real theta;
		if (eigenvalue >= 0.) {
			rTilde = deltaQTildeL[i] / deltaQTilde[i];
			theta = 1.;
#ifdef SOLID
			if (solidL2) rTilde = 1.;
#endif	//SOLID
		} else {
			rTilde = deltaQTildeR[i] / deltaQTilde[i];
			theta = -1.;
#ifdef SOLID
			if (solidR2) rTilde = 1.;
#endif	//SOLID
		}
		real phi = slopeLimiter(rTilde);
		real epsilon = eigenvalue * dt_dx;

		real deltaFluxTilde = eigenvalue * deltaQTilde[i];
		fluxTilde[i] -= .5 * deltaFluxTilde * (theta + phi * (epsilon - theta));
	}

	rightEigenvectorTransform(flux, eigenvectors, fluxTilde, side);
}

__kernel void calcFlux(
	__global real* fluxBuffer,
	const __global real* stateBuffer,
	const __global real* eigenvaluesBuffer,
	const __global real* eigenvectorsBuffer,
	const __global real* deltaQTildeBuffer,
	real dt
#ifdef SOLID
	, const __global char* solidBuffer
#endif	//SOLID
)
{
	for (int side = 0; side < DIM; ++side) {
		calcFluxSide(fluxBuffer, stateBuffer, eigenvaluesBuffer, eigenvectorsBuffer, deltaQTildeBuffer, dt, side
#ifdef SOLID
			, solidBuffer
#endif
		);
	}
}
