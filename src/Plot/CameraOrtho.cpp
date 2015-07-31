#include "HydroGPU/Plot/CameraOrtho.h"
#include "HydroGPU/HydroGPUApp.h"
#include <OpenGL/gl.h>

namespace HydroGPU {
namespace Plot {

CameraOrtho::CameraOrtho(HydroGPU::HydroGPUApp* app_)
: Super(app_)
, zoom(1.f)
{
	if (!app->lua.ref()["camera"]["pos"].isNil()) {
		app->lua.ref()["camera"]["pos"][1] >> pos(0);
		app->lua.ref()["camera"]["pos"][2] >> pos(1);
	}
	app->lua.ref()["camera"]["zoom"] >> zoom;
}

void CameraOrtho::setupProjection() {
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	glOrtho(-app->aspectRatio *.5, app->aspectRatio * .5, -.5, .5, -1., 1.);
}

void CameraOrtho::setupModelview() {
	glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();
	glScalef(zoom, zoom, zoom);
	glTranslatef(-pos(0), -pos(1), 0);
}

void CameraOrtho::mousePan(int dx, int dy) {
	pos += Tensor::Vector<float,2>(
		-(float)dx * app->aspectRatio / (float)app->screenSize(0),
		(float)dy / (float)app->screenSize(1)
	) / zoom;
}

void CameraOrtho::mouseZoom(int dz) {
	float scale = exp((float)dz * -.03f);
	zoom *= scale;
}


}
}
