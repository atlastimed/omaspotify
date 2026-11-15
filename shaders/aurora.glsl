// Curtains of light across the whole view. Low, middle and high each move one
// curtain; its lower edge is bright and its light trails upward, lined with
// fine rays that the spectrum leans on.

// v runs down the visualiser's own room, 0 at its top. The bright lower edges
// stay inside it; only the soft light above them rises behind what is on the
// view.
float curtain(float x, float v, float k, float heard) {
  float line = 0.84 - k * 0.27
    + 0.07 * sin(x * (2.3 + k * 1.1) + time * (0.21 + k * 0.08) + k * 1.9)
    + 0.035 * sin(x * (6.3 - k) - time * (0.29 + k * 0.05) + k);
  // The curtain lifts where its part of the spectrum is loud.
  line -= 0.08 * heard + 0.06 * curve(bandAt(x)) * (0.4 + heard);
  line = max(line, 0.06);
  float above = line - v;
  float tall = 0.3 + 0.6 * heard;
  float body = above > 0.0 ? exp(-above / tall) : exp(above / 0.02);
  float edge = exp(-abs(above) / 0.011);
  float rays = 0.62 + 0.38 * sin(x * (130.0 + k * 53.0) + sin(time * 0.5 + k * 2.0) * 3.0
    + sin(x * 17.0 + time * 0.3) * 2.0);
  rays = mix(1.0, rays, smoothstep(0.0, 0.08, above));
  return (body * rays * (0.22 + 0.9 * heard) + edge * (0.25 + 0.6 * heard));
}

void main() {
  vec2 space = room();
  float x = qt_TexCoord0.x;
  float v = (qt_TexCoord0.y * area.y - space.x) / space.y;
  float low = curtain(x, v, 0.0, bass);
  float middle = curtain(x, v, 1.0, mid);
  float high = curtain(x, v, 2.0, treble);
  vec3 rgb = c0.rgb * low + c1.rgb * middle + c2.rgb * high;
  float alpha = clamp(max(low, max(middle, high)) * (0.6 + 0.4 * glow), 0.0, 1.0);
  float peak = max(rgb.r, max(rgb.g, rgb.b));
  fragColor = lit(peak > 0.0 ? rgb / max(peak, 1.0) / max(alpha, 1e-3) * alpha : rgb, alpha);
}
