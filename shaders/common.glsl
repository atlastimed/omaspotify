#version 440

// Shared by every visualiser style. scripts/build-shaders.sh puts this in front
// of each style and compiles the pair with qsb.
//
// The spectrum arrives as a one-row texture, one texel per band:
// red is the level, green the slowly falling peak above it.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  float time;      // seconds, stops while nothing plays
  float count;     // bands in the texture
  float glow;      // 0..1
  float mirror;    // 1 puts the bass in the middle
  float peaks;     // 1 draws the falling caps
  float bass;      // 0..1 energy of the low, middle and high thirds
  float mid;
  float treble;
  float strength;  // 0..1 overall brightness
  float span;      // pixels of room around the artwork
  float deck;      // pixels down to where nothing else is drawn
  vec2 area;       // this item, in pixels
  vec4 art;        // the artwork inside it: x, y, width, height
  vec4 c0;         // palette, low to high
  vec4 c1;
  vec4 c2;
};

layout(binding = 1) uniform sampler2D bands;

vec2 band(float i) {
  float at = (clamp(i, 0.0, count - 1.0) + 0.5) / count;
  return texture(bands, vec2(at, 0.5)).rg;
}

// A smooth curve through the levels, for the styles that are not bars.
float curve(float x) {
  float i = floor(x);
  float f = x - i;
  float a = band(i - 1.0).r;
  float b = band(i).r;
  float c = band(i + 1.0).r;
  float d = band(i + 2.0).r;
  float v = b + 0.5 * f * (c - a + f * (2.0 * a - 5.0 * b + 4.0 * c - d
    + f * (3.0 * (b - c) + d - a)));
  return clamp(v, 0.0, 1.0);
}

// Where along the spectrum a horizontal position falls, as a band number.
float bandAt(float x) {
  float t = mirror > 0.5 ? abs(x - 0.5) * 2.0 : x;
  return t * count;
}

vec3 palette(float t) {
  t = clamp(t, 0.0, 1.0);
  return t < 0.5 ? mix(c0.rgb, c1.rgb, t * 2.0) : mix(c1.rgb, c2.rgb, t * 2.0 - 1.0);
}

float roundBox(vec2 p, vec2 extent, float r) {
  vec2 q = abs(p) - extent + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// The part of the view that is the visualiser's alone: from the deck, under
// the artwork and the names, to the bottom. x is its top, y its height.
vec2 room() {
  float top = clamp(deck, 0.0, area.y * 0.8);
  return vec2(top, area.y - top);
}

// Colour and coverage in, premultiplied out, which is what the scene expects.
vec4 lit(vec3 rgb, float a) {
  a = clamp(a, 0.0, 1.0) * strength * qt_Opacity;
  return vec4(rgb * a, a);
}
