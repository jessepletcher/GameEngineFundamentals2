shader_type spatial;
render_mode unshaded, cull_disabled;

// Keep the existing beach illustration intact. These masks render just the
// lighthouse or ship over the separate, already-authored scenery layers.
uniform sampler2D illustration : source_color, filter_nearest;
uniform bool lighthouse = true;

bool rect(vec2 p, vec4 bounds) {
	return p.x >= bounds.x && p.y >= bounds.y && p.x < bounds.z && p.y < bounds.w;
}

void fragment() {
	vec2 p = floor(UV * vec2(384.0, 216.0));
	bool keep;
	if (lighthouse) {
		keep = rect(p, vec4(289, 126, 314, 134))
			|| rect(p, vec4(290, 114, 312, 126))
			|| rect(p, vec4(291, 113, 311, 114))
			|| rect(p, vec4(292, 85, 310, 113))
			|| rect(p, vec4(291, 83, 311, 85))
			|| rect(p, vec4(297, 73, 306, 83))
			|| rect(p, vec4(292, 76, 311, 78))
			|| rect(p, vec4(297, 63, 299, 73))
			|| rect(p, vec4(301, 63, 303, 73))
			|| rect(p, vec4(305, 63, 306, 73))
			|| rect(p, vec4(302, 57, 303, 61))
			|| (p.y >= 60.0 && p.y < 65.0 && abs(p.x - 301.5) <= (p.y - 59.0));
	} else {
		keep = rect(p, vec4(135, 100, 157, 103))
			|| (p.y >= 101.0 && p.y < 108.0 && p.x >= 128.0 + max(0.0, p.y - 102.0)
				&& p.x < (p.y < 106.0 ? 160.0 : 158.0));
	}
	if (!keep) { discard; }
	ALBEDO = texture(illustration, UV).rgb;
	ALPHA = COLOR.a;
}
