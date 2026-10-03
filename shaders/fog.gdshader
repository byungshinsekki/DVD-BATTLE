shader_type canvas_item;
// 시야 마스크(흰색 = 보임)를 부드럽게 흐려 안개로 바꾼다.
uniform vec4 fog_color : source_color = vec4(0.015, 0.02, 0.045, 1.0);
uniform float strength = 0.8;
uniform float t = 0.0;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float m = texture(TEXTURE, UV).r * 0.28;
	m += texture(TEXTURE, UV + vec2(px.x * 1.5, 0.0)).r * 0.12;
	m += texture(TEXTURE, UV - vec2(px.x * 1.5, 0.0)).r * 0.12;
	m += texture(TEXTURE, UV + vec2(0.0, px.y * 1.5)).r * 0.12;
	m += texture(TEXTURE, UV - vec2(0.0, px.y * 1.5)).r * 0.12;
	m += texture(TEXTURE, UV + px * 1.2).r * 0.06;
	m += texture(TEXTURE, UV - px * 1.2).r * 0.06;
	m += texture(TEXTURE, UV + vec2(px.x, -px.y) * 1.2).r * 0.06;
	m += texture(TEXTURE, UV + vec2(-px.x, px.y) * 1.2).r * 0.06;
	float n1 = sin(UV.x * 23.0 + t * 0.35) * sin(UV.y * 17.0 - t * 0.27);
	float n2 = sin((UV.x + UV.y) * 41.0 - t * 0.6) * 0.5;
	float mist = 0.9 + 0.07 * n1 + 0.03 * n2;
	float a = clamp((1.0 - m), 0.0, 1.0) * strength * mist;
	// 경계에 옅은 푸른 테두리
	float edge = smoothstep(0.15, 0.5, m) * (1.0 - smoothstep(0.5, 0.85, m));
	vec3 col = mix(fog_color.rgb, vec3(0.25, 0.45, 0.8), edge * 0.35);
	COLOR = vec4(col, a + edge * 0.08);
}
