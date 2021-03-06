#include "HydroGPU/Shared/Common.h"

__kernel void calcMagneticFieldDivergence(
	__global real* magneticFieldDivergenceBuffer,
	const __global real* stateBuffer)
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

	real divergence = (stateBuffer[STATE_MAGNETIC_FIELD_X + NUM_STATES * (index + stepsize.x)]
		- stateBuffer[STATE_MAGNETIC_FIELD_X + NUM_STATES * (index - stepsize.x)]) / (2. * DX);
#if DIM > 1
	divergence += (stateBuffer[STATE_MAGNETIC_FIELD_Y + NUM_STATES * (index + stepsize.y)]
		- stateBuffer[STATE_MAGNETIC_FIELD_Y + NUM_STATES * (index - stepsize.y)]) / (2. * DY);
#endif
#if DIM > 2
	divergence += (stateBuffer[STATE_MAGNETIC_FIELD_Z + NUM_STATES * (index + stepsize.z)]
		- stateBuffer[STATE_MAGNETIC_FIELD_Z + NUM_STATES * (index - stepsize.z)]) / (2. * DZ);
#endif

	magneticFieldDivergenceBuffer[index] = divergence;
}

__kernel void magneticPotentialPoissonRelax(
	__global real* magneticFieldPotentialWriteBuffer,
	const __global real* magneticFieldPotentialReadBuffer,
	const __global real* magneticFieldDivergenceBuffer)
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

	real sum = (magneticFieldPotentialReadBuffer[index + stepsize.x] + magneticFieldPotentialReadBuffer[index - stepsize.x]) / (DX * DX);
#if DIM > 1
	sum += (magneticFieldPotentialReadBuffer[index + stepsize.y] + magneticFieldPotentialReadBuffer[index - stepsize.y]) / (DY * DY);
#endif
#if DIM > 2
	sum += (magneticFieldPotentialReadBuffer[index + stepsize.z] + magneticFieldPotentialReadBuffer[index - stepsize.z]) / (DZ * DZ);
#endif

	const real denom = -2. * (1. / (DX * DX)
#if DIM > 1
		+ 1. / (DY * DY)
#endif
#if DIM > 2
		+ 1. / (DZ * DZ)
#endif
	);

	//TODO double-buffer?
	magneticFieldPotentialWriteBuffer[index] = (magneticFieldDivergenceBuffer[index] - sum) / denom;
}

__kernel void magneticFieldRemoveDivergence(
	__global real* stateBuffer,
	const __global real* magneticFieldPotentialBuffer)
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

	stateBuffer[STATE_MAGNETIC_FIELD_X + NUM_STATES * index] -= (magneticFieldPotentialBuffer[index + stepsize.x] - magneticFieldPotentialBuffer[index - stepsize.x]) / (2. * DX);
#if DIM > 1
	stateBuffer[STATE_MAGNETIC_FIELD_Y + NUM_STATES * index] -= (magneticFieldPotentialBuffer[index + stepsize.y] - magneticFieldPotentialBuffer[index - stepsize.y]) / (2. * DY);
#endif
#if DIM > 2
	stateBuffer[STATE_MAGNETIC_FIELD_Z + NUM_STATES * index] -= (magneticFieldPotentialBuffer[index + stepsize.z] - magneticFieldPotentialBuffer[index - stepsize.z]) / (2. * DZ);
#endif
}
