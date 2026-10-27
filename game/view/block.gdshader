// The blocks' pixel textures (issue #206): each face samples a layer of BlockTextures' array and
// multiplies the block's colour by it. Lit like the StandardMaterial3D it replaces, so the sun's
// shadows and the three-tone look of tops and sides stay as they were.
shader_type spatial;
render_mode cull_back;

uniform sampler2DArray layers : filter_nearest_mipmap, repeat_enable;
// MultiMesh blocks carry their finish in INSTANCE_CUSTOM and their colour in COLOR. A lone mesh
// (a resident's or an animal's part) sets these instead.
uniform bool from_instance = true;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 finish = vec3(0.0);
// A map-wide grade: the mines are colder and harsher than the village (issue #206).
uniform vec3 grade : source_color = vec3(1.0);
uniform float contrast = 1.0;

varying vec3 wpos;
varying vec3 wnormal;
varying vec3 lpos;
varying flat vec3 lay;
varying flat int end_axis;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	lpos = VERTEX + 0.5;
	lay = from_instance ? floor(INSTANCE_CUSTOM.rgb * 255.0 + 0.5) : finish;
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	end_axis = int(lay.z) - 1;
	if (end_axis < 0) {  // the longest axis, ties going to y
		end_axis = 1;
		if (s.x > s.y && s.x >= s.z) {
			end_axis = 0;
		} else if (s.z > s.y && s.z > s.x) {
			end_axis = 2;
		}
	}
	if (from_instance && !OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	}
}

void fragment() {
	vec3 a = abs(wnormal);
	int axis = a.x > a.y && a.x > a.z ? 0 : (a.y >= a.z ? 1 : 2);
	vec2 uv;
	float layer;
	if (axis == end_axis) {
		// Fitted to the face, so a log's rings sit in the middle of its end.
		uv = axis == 1 ? lpos.xz : (axis == 0 ? vec2(lpos.z, 1.0 - lpos.y) : vec2(lpos.x, 1.0 - lpos.y));
		layer = lay.y;
	} else {
		// Laid in world space, so neighbouring blocks tile. The texture's v runs along the box's
		// long axis when the face holds it, so grain follows a board or a trunk. One texture per block.
		if (axis == 1) {
			uv = end_axis == 0 ? wpos.zx : wpos.xz;
		} else if (axis == 0) {
			uv = end_axis == 2 ? vec2(-wpos.y, wpos.z) : vec2(wpos.z, -wpos.y);
		} else {
			uv = end_axis == 0 ? vec2(-wpos.y, wpos.x) : vec2(wpos.x, -wpos.y);
		}
		layer = lay.x;
	}
	vec3 shade = texture(layers, vec3(uv, layer)).rgb * 2.0;
	shade = mix(vec3(1.0), shade, contrast);
	vec4 base = from_instance ? COLOR : tint;
	ALBEDO = base.rgb * shade * grade;
	ROUGHNESS = 1.0;
	//ALPHA
}
