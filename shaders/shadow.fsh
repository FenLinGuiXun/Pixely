#version 460 compatibility

uniform sampler2D gtexture;
const float shadowDistanceRenderMul = 1.0;

in vec2 texcoord;
in vec4 glcolor;

layout(location = 0) out vec4 color;

void main() {
  color = texture(gtexture, texcoord) * glcolor;
  if(color.a < 0.1){
    discard;
  }
}
