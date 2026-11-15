// Curtains of light across the whole view. Low, middle and high each move one
// curtain; its lower edge is bright and its light trails upward, lined with
// fine rays that the spectrum leans on.

float curtain(vec2 uv, float k, float heard) {
  float x = uv.x;
  float line = 0.8 - k * 0.2
    + 0.06 * sin(x * (2.3 + k * 1.1) + time * (0.21 + k * 0.08) + k * 1.9)
    + 0.03 * sin(x * (6.3 - k) - time * (0.29 + k * 0.05) + k);
  // The curtain lifts where its part of the spectrum is loud.
  line -= 0.07 * heard + 0.05 * curve(bandAt(x)) * (0.4 + heard);
  float above = line - uv.y;
  float tall = 0.16 + 0.34 * heard;
  float body = above > 0.0 ? exp(-above / tall) : exp(above / 0.012);
  float edge = exp(-abs(above) / 0.006);
  float rays = 0.62 + 0.38 * sin(x * (130.0 + k * 53.0) + sin(time * 0.5 + k * 2.0) * 3.0
    + sin(x * 17.0 + time * 0.3) * 2.0);
  rays = mix(1.0, rays, smoothstep(0.0, 0.05, above));
  return (body * rays * (0.22 + 0.9 * heard) + edge * (0.25 + 0.6 * heard));
}

void main() {
  vec2 uv = qt_TexCoord0;
  float low = curtain(uv, 0.0, bass);
  float middle = curtain(uv, 1.0, mid);
  float high = curtain(uv, 2.0, treble);
  vec3 rgb = c0.rgb * low + c1.rgb * middle + c2.rgb * high;
  float alpha = clamp(max(low, max(middle, high)) * (0.6 + 0.4 * glow), 0.0, 1.0);
  float peak = max(rgb.r, max(rgb.g, rgb.b));
  fragColor = lit(peak > 0.0 ? rgb / max(peak, 1.0) / max(alpha, 1e-3) * alpha : rgb, alpha);
}
