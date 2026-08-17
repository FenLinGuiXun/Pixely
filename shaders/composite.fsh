#version 460 compatibility
#include "/lib/distort.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex0;


in vec2 texcoord;

const vec3 blocklightColor = vec3(1.0, 0.5, 0.08);
const vec3 skylightColor = vec3(0.05, 0.15, 0.3);
const vec3 sunlightColor = vec3(1.0);
const vec3 ambientColor = vec3(0.1);
const int shadowMapResolution = 2048;

uniform vec3 shadowLightPosition;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;


/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

vec3 projectAndDivide(mat4 projectionMatrix, vec3 position);

void main() {

	vec2 lightmap = texture(colortex1, texcoord).rg; // we only need the r and g components
	vec3 encodedNormal = texture(colortex2, texcoord).rgb;
	vec3 normal = normalize((encodedNormal - 0.5) * 2.0); // we normalize to make sure it is of unit length

	color = texture(colortex0, texcoord);

	float depth = texture(depthtex0, texcoord).r;
	if (depth == 1.0) {
		return;
	}

	vec3 blocklight = lightmap.r * blocklightColor;
	vec3 skylight = lightmap.g * skylightColor;
	vec3 lightVector = normalize(shadowLightPosition);
	vec3 worldLightVector = mat3(gbufferModelViewInverse) * lightVector;
	vec3 ambient = ambientColor;

	vec3 NDCPos = vec3(texcoord.xy, depth) * 2.0 - 1.0;
	vec3 viewPos = projectAndDivide(gbufferProjectionInverse, NDCPos);
	vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
	vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos, 1.0)).xyz;
	vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
	shadowClipPos.z -= 0.001; // bias
	shadowClipPos.xyz = distortShadowClipPos(shadowClipPos.xyz); // distortion
	vec3 shadowNDCPos = shadowClipPos.xyz / shadowClipPos.w;
	vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5;
	float shadow = step(shadowScreenPos.z, texture(shadowtex0, shadowScreenPos.xy).r);
	vec3 sunlight = sunlightColor * clamp(dot(worldLightVector, normal), 0.0, 1.0) * shadow;

	color.rgb = pow(color.rgb, vec3(2.2)); //convert to linear color space
	color.rgb *= blocklight + skylight + ambient + sunlight;
	color.rgb = pow(color.rgb, vec3(1.0 / 2.2)); //deconvert from linear color for monitor
}

vec3 projectAndDivide(mat4 projectionMatrix, vec3 position){
  vec4 homPos = projectionMatrix * vec4(position, 1.0);
  return homPos.xyz / homPos.w;
}
