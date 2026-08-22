#version 460 compatibility
#include "/lib/distort.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform int worldTime;


in vec2 texcoord;

const vec3 blocklightColor = vec3(1.0, 0.5, 0.08);
const vec3 skylightColor = vec3(0.05, 0.15, 0.3);
const vec3 sunlightColor = vec3(1.0);
const vec3 moonlightColor = vec3(0.05, 0.15, 0.3);
const vec3 ambientColor = vec3(0.1);

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;


/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

vec3 projectAndDivide(mat4 projectionMatrix, vec3 position);
vec3 getShadow(vec3 shadowScreenPos);
vec3 getSoftShadow(vec4 shadowClipPos);

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
	vec3 lightVector = normalize(sunPosition);
	vec3 worldSunlightVector = mat3(gbufferModelViewInverse) * lightVector;
	vec3 moonLightVector = normalize(moonPosition);
  vec3 worldMoonlightVector = mat3(gbufferModelViewInverse) * moonLightVector;
	vec3 ambient = ambientColor;
	
  float moonShadowStrength = 0.0;
  float time = float(worldTime);

  if (time >= 12000.0 && time < 14000.0) {
    // Fade in after sunset
    moonShadowStrength = smoothstep(12000.0, 14000.0, time);
  }
  else if (time >= 14000.0 && time < 22000.0) {
    // Full moon shadows through most of the night
    moonShadowStrength = 1.0;
  }
  else if (time >= 22000.0) {
    // Fade out toward sunrise
    moonShadowStrength = 1.0 - smoothstep(22000.0, 24000.0, time);
  }

	vec3 NDCPos = vec3(texcoord.xy, depth) * 2.0 - 1.0;
	vec3 viewPos = projectAndDivide(gbufferProjectionInverse, NDCPos);
	vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
	vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos, 1.0)).xyz;
	vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
	vec3 shadow = getSoftShadow(shadowClipPos);
	
  float sunVisibility = clamp(worldSunlightVector.y * 10.0, 0.0, 1.0);
  vec3 sunlight =
    sunlightColor
    * clamp(dot(worldSunlightVector, normal), 0.0, 1.0)
    * shadow
    * sunVisibility;

  float moonVisibility = clamp(worldMoonlightVector.y * 10.0, 0.0, 1.0);
  vec3 moonShadow = mix(
    vec3(1.0),
    shadow,
    moonShadowStrength
  );

  vec3 moonlight =
    moonlightColor
    * clamp(dot(worldMoonlightVector, normal), 0.0, 1.0)
    * moonVisibility
    * moonShadow;

	color.rgb = pow(color.rgb, vec3(2.2)); //convert to linear color space
	color.rgb *= blocklight + skylight + ambient + sunlight + moonlight;
	color.rgb = pow(color.rgb, vec3(1.0 / 2.2)); //deconvert from linear color for monitor
}

vec3 projectAndDivide(mat4 projectionMatrix, vec3 position){
  vec4 homPos = projectionMatrix * vec4(position, 1.0);
  return homPos.xyz / homPos.w;
}

vec3 getShadow(vec3 shadowScreenPos){
  float transparentShadow = step(shadowScreenPos.z, texture(shadowtex0, shadowScreenPos.xy).r); // sample the shadow map containing everything

  /*
  note that a value of 1.0 means 100% of sunlight is getting through
  not that there is 100% shadowing
  */

  if(transparentShadow == 1.0){
    /*
    since this shadow map contains everything,
    there is no shadow at all, so we return full sunlight
    */
    return vec3(1.0);
  }

  float opaqueShadow = step(shadowScreenPos.z, texture(shadowtex1, shadowScreenPos.xy).r); // sample the shadow map containing only opaque stuff

  if(opaqueShadow == 0.0){
    // there is a shadow cast by something opaque, so we return no sunlight
    return vec3(0.0);
  }

  // contains the color and alpha (transparency) of the thing casting a shadow
  vec4 shadowColor = texture(shadowcolor0, shadowScreenPos.xy);


  /*
  we use 1 - the alpha to get how much light is let through
  and multiply that light by the color of the caster
  */
  return shadowColor.rgb * (1.0 - shadowColor.a);
}

vec3 getSoftShadow(vec4 shadowClipPos){
  vec3 shadowAccum = vec3(0.0); // sum of all shadow samples
  const int samples = SHADOW_RANGE * SHADOW_RANGE * 4; // we are taking 2 * SHADOW_RANGE * 2 * SHADOW_RANGE samples

  for(int x = -SHADOW_RANGE; x < SHADOW_RANGE; x++){
    for(int y = -SHADOW_RANGE; y < SHADOW_RANGE; y++){
      vec2 offset = vec2(x, y) * SHADOW_RADIUS / float(SHADOW_RANGE);
      offset /= shadowMapResolution; // offset in the rotated direction by the specified amount. We divide by the resolution so our offset is in terms of pixels
      vec4 offsetShadowClipPos = shadowClipPos + vec4(offset, 0.0, 0.0); // add offset
      offsetShadowClipPos.z -= 0.005; // apply bias
      offsetShadowClipPos.xyz = distortShadowClipPos(offsetShadowClipPos.xyz); // apply distortion
      vec3 shadowNDCPos = offsetShadowClipPos.xyz / offsetShadowClipPos.w; // convert to NDC space
      vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5; // convert to screen space
      shadowAccum += getShadow(shadowScreenPos); // take shadow sample
    }
  }

  return shadowAccum / float(samples); // divide sum by count, getting average shadow
}
