varying vec3 color;

#ifdef VERTEX_SHADER

uniform float xmin, xmax;
uniform sampler2D tex;
uniform int channel;

void main() {
	vec3 vertex = gl_Vertex.xyz;
	vertex.y = texture2D(tex, vertex.xy)[channel];
	vertex.x = vertex.x * (xmax - xmin) + xmin;
	color = vec3(0.);
	color[channel] = 1.;
	gl_Position = gl_ModelViewProjectionMatrix * vec4(vertex, 1.);
}

#endif	//VERTEX_SHADER

#ifdef FRAGMENT_SHADER

void main() {
	gl_FragColor = vec4(color, 1.);
}

#endif	//FRAGMENT_SHADER
