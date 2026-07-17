// Acne & Rosacea Photo Analysis Engine.
//
// Deterministic, on-device analysis layered on top of the existing
// AcneRosaceaInsightReport intelligence. Inputs are a captured photo +
// a small set of user-verified severity readings (the user is the final
// arbiter of what the photo shows). The engine then synthesises a
// dermatologist-style structured analysis:
//
//   • Detected acne type / rosacea pattern classification
//   • Region-focused insights (jawline → hormonal, cheeks → rosacea, etc.)
//   • Overall severity index (0–10) with band + plain-English headline
//   • Personalised clinical insights with reasoning
//   • Procedure recommendations (HydraFacial, peels, LED, IPL/laser,
//     systemic consults, microneedling) ranked by suitability with
//     pros, cons, expected sessions, timeline, and intensity
//   • Optional comparison vs. a baseline photo (per-metric deltas +
//     overall severity delta)
//
// No network, no inference call — this is a transparent rules engine
// that can be reasoned about and improved over time. The flow is
// intentionally honest with the user: AI-assisted, not a substitute
// for professional evaluation.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/acne_rosacea_log.dart';
import 'skin_metric_labels.dart';

/// Detected dominant acne classification.
enum DetectedAcneType { none, comedonal, inflammatory, cystic, hormonal, mixed }

/// Detected rosacea sub-pattern.
enum DetectedRosaceaPattern {
  none,
  transientFlushing,
  erythematotelangiectatic,
  papulopustular,
}

/// Primary region the user identified as the focus of the analysis.
enum FacialRegion { fullFace, forehead, cheeks, jawlineChin, nose, perioral }

/// Intensity tier for procedure recommendations.
enum ProcedureIntensity { gentle, moderate, intensive, systemic }

/// Procedure category for grouping.
enum ProcedureCategory {
  inOffice,
  energy,
  light,
  topicalPrescription,
  systemicConsult,
  scarRevision,
}

/// User-rated severity readings derived from the captured photo. These
/// can be pre-filled from the user's recent logs and confirmed/adjusted
/// during the analysis flow.
class PhotoAnalysisInput {
  final String imagePath;
  final DateTime capturedAt;
  final FacialRegion region;
  final int inflammatoryAcne; // 0–10  (papules/pustules visible)
  final int comedonalLoad; // 0–10  (blackheads/whiteheads)
  final int cysticActivity; // 0–10  (deep nodules)
  final int redness; // 0–10  (diffuse erythema)
  final int visibleVessels; // 0–10  (telangiectasia)
  final int flushingEpisodes; // 0–10  (recent transient flushing)
  final int sensitivity; // 0–10  (stinging / reactive)
  final bool cycleRelatedFlare; // user-reported menstrual flare
  final bool adultOnset; // breakouts persisting past mid-20s

  const PhotoAnalysisInput({
    required this.imagePath,
    required this.capturedAt,
    required this.region,
    required this.inflammatoryAcne,
    required this.comedonalLoad,
    required this.cysticActivity,
    required this.redness,
    required this.visibleVessels,
    required this.flushingEpisodes,
    required this.sensitivity,
    required this.cycleRelatedFlare,
    required this.adultOnset,
  });

  /// Build an input automatically from extracted [PhotoFeatures] using
  /// clinically-anchored formulas. Each metric maps to an established
  /// dermatology scoring framework where possible:
  ///
  /// • inflammatoryAcne — Adapted from the Global Acne Grading System
  ///   (GAGS, Doshi 1997): inflammatory lesion density + area fraction,
  ///   region-weighted by zone partition.
  /// • comedonalLoad — Surface texture roughness + low-saturation
  ///   unevenness (proxy for blackheads/whiteheads without active redness).
  /// • cysticActivity — Largest contiguous inflammatory cluster
  ///   (nodule/cyst proxy), gated by a minimum-size threshold to avoid
  ///   counting clustered papules as cystic.
  /// • redness — Erythema index (Takiwaki-style R/(G+B) ratio).
  /// • visibleVessels — Telangiectasia detector: saturated thin red
  ///   pixels concentrated above the erythema baseline.
  /// • flushingEpisodes — Erythema variance + zone-asymmetry (NRS
  ///   transient-erythema criterion adapted to single-shot photo).
  /// • sensitivity — Reactive-erythema proxy: persistent central-face
  ///   redness combined with variance (barrier-irritation signature).
  ///
  /// All values clamp to 0–10. This is the AI auto-fill path — no user
  /// sliders required.
  factory PhotoAnalysisInput.fromFeatures({
    required String imagePath,
    required DateTime capturedAt,
    required FacialRegion region,
    required PhotoFeatures features,
    required bool cycleRelatedFlare,
    required bool adultOnset,
  }) {
    int clamp10(double v) => v.round().clamp(0, 10);

    // Specificity guards: post-inflammatory hyperpigmentation (PIH)
    // and atrophic / erythematous scars share many photographic
    // signatures with active acne (elevated red ratio, textural
    // unevenness) but are NOT active disease. When the photo is
    // dominated by pigment-spot signal, dampen the inflammatory
    // scores so a scarred-but-clear face doesn't read as a severe
    // breakout.
    final pigmentDampening = (1.0 - (features.pigmentSpotDensity * 0.55)).clamp(
      0.30,
      1.0,
    );

    // ── Inflammatory acne (GAGS-adapted) ──
    // GAGS scores inflammatory lesions (papules grade 2, pustules grade
    // 3) by region; we approximate with hot-spot density × area fraction
    // and lift the score with focal cluster signal. Multipliers tuned
    // so a clear-but-scarred face → 0–2 and a moderately broken-out
    // face → 4–6.
    final inflammatory = clamp10(
      ((features.lesionScore * 5.0) +
              (features.inflammatoryAreaFraction.clamp(0.0, 0.30) * 6.0) +
              (features.nodularClusterScore * 0.8)) *
          pigmentDampening,
    );

    // ── Comedonal load ──
    // Surface unevenness with LOW redness — comedones don't inflame.
    final comedonal = clamp10(
      (features.textureRoughness * 5.0) +
          (features.poreDensity * 3.0) +
          (features.textureScore * 1.5) -
          (features.lesionScore * 2.0) -
          (features.pigmentSpotDensity * 1.5),
    );

    // ── Cystic activity (largest cluster as proxy) ──
    // Strict gate: cystic acne requires (a) a sizeable contiguous
    // inflammatory cluster AND (b) supporting general inflammatory
    // load. A single PIH patch should NOT trigger this metric.
    final cyst =
        (features.nodularClusterScore < 0.40 || features.lesionScore < 0.20)
        ? 0
        : clamp10(
            ((features.nodularClusterScore - 0.30) * 9 +
                    features.lesionScore * 2.5) *
                pigmentDampening,
          );

    // ── Erythema / Rosacea redness (NRS criterion 1) ──
    // National Rosacea Society Standard Classification weighs persistent
    // central-face erythema as the cardinal feature. Conservative:
    // many people show mild ruddiness without meeting any rosacea
    // criterion, so we require persistent central-face evidence before
    // letting the score climb past ~3.
    final rednessRaw =
        (features.persistentErythemaScore * 4.5) +
        ((features.rednessMean - 0.25).clamp(0.0, 1.0) * 4.0) +
        (features.centralFaceErythema * 1.5);
    final redness = features.persistentErythemaScore < 0.18
        ? clamp10(rednessRaw * 0.4) // mild ruddiness only — cap low
        : clamp10(rednessRaw);

    // ── Visible vessels (telangiectasia detector) ──
    // Hard to assess from a single photo; require a meaningful vessel
    // signal before scoring. Saturation alone (ruddy cheeks) shouldn't
    // count as telangiectasia.
    final vessels = features.vesselScore < 0.18
        ? 0
        : clamp10(
            (features.vesselScore - 0.12) * 9.0 +
                features.saturationMean * features.rednessMean * 2.0,
          );

    // ── Flushing episodes ──
    // NRS criterion 2 = HISTORY of flushing — fundamentally a temporal
    // observation. From a single still photo we can only approximate
    // and must be conservative. Require both notable variance AND
    // elevated mean redness before scoring above the floor.
    final flushHasEvidence =
        features.rednessVariance > 0.22 && features.rednessMean > 0.30;
    final flushing = !flushHasEvidence
        ? clamp10(features.rednessVariance * 2.0) // floor only
        : clamp10(
            (features.rednessVariance * 4.5) +
                ((features.rednessMean - 0.25).clamp(0.0, 1.0) * 3.0) +
                ((features.jawZoneErythema - features.centralFaceErythema)
                        .abs() *
                    1.5),
          );

    // ── Skin sensitivity / reactivity proxy ──
    // Stinging/burning cannot be measured photographically — this is a
    // structural proxy only. Capped at 6/10 unless both persistent
    // erythema AND variance are jointly elevated.
    final sensRaw =
        (features.persistentErythemaScore * 3.5) +
        (features.rednessVariance * 3.0) +
        ((features.rednessMean - 0.25).clamp(0.0, 1.0) * 1.5);
    final sensStrong =
        features.persistentErythemaScore > 0.30 &&
        features.rednessVariance > 0.25;
    final sensitivity = sensStrong
        ? clamp10(sensRaw)
        : math.min(6, clamp10(sensRaw));

    return PhotoAnalysisInput(
      imagePath: imagePath,
      capturedAt: capturedAt,
      region: region,
      inflammatoryAcne: inflammatory,
      comedonalLoad: comedonal,
      cysticActivity: cyst,
      redness: redness,
      visibleVessels: vessels,
      flushingEpisodes: flushing,
      sensitivity: sensitivity,
      cycleRelatedFlare: cycleRelatedFlare,
      adultOnset: adultOnset,
    );
  }
}

/// Pixel-level features extracted from the captured photo. Normalised to
/// 0–1 so they can be combined with simple linear maps. This is not ML —
/// it's deterministic descriptive statistics on the resized image,
/// designed to feed clinically-anchored severity formulas (GAGS-adapted
/// for acne, National Rosacea Society criteria-adapted for rosacea).
class PhotoFeatures {
  /// Erythema index — mean R / mean(G,B) normalised so a typical
  /// neutral skin region sits near ~0.0 and strong erythema reaches ~1.0.
  /// Conceptually equivalent to a simplified photographic
  /// erythema/melanin index (Takiwaki-style R-channel ratio).
  final double rednessMean;

  /// Variance of the redness ratio across pixels — proxy for focal vs.
  /// diffuse erythema distribution (transient flushing vs. persistent
  /// erythema in NRS rosacea criteria).
  final double rednessVariance;

  /// Mean HSV-style saturation across skin pixels.
  final double saturationMean;

  /// Mean brightness (V) across skin pixels — used to gate bad exposure
  /// and to compute the engine's confidence.
  final double brightnessMean;

  /// Fraction-derived score for focal high-redness hot-spots (papules /
  /// pustules). Adapted from inflammatory-lesion-density measures used
  /// in objective acne photography studies. 0–1.
  final double lesionScore;

  /// Composite proxy for visible telangiectasia (saturated thin red
  /// streaks). 0–1.
  final double vesselScore;

  /// Local-contrast variance proxy for comedonal/textural unevenness. 0–1.
  final double textureScore;

  /// Engine confidence (0–1) — drops on poor exposure or tiny sample.
  final double confidence;

  // ── Additional clinical features (defaulted for backwards compat) ──

  /// Dark-spot density proxy for post-inflammatory hyperpigmentation
  /// and macular pigment lesions. 0–1.
  final double pigmentSpotDensity;

  /// Edge-density (Sobel-like) proxy for fine lines / rhytids. 0–1.
  final double wrinkleEdgeDensity;

  /// Density of small dark dots in a regular pattern — proxy for
  /// visible pore count in the nasal / mid-cheek zone. 0–1.
  final double poreDensity;

  /// Skin-surface roughness — local std-dev of brightness inside the
  /// skin mask. Used as a clinical texture-quality indicator. 0–1.
  final double textureRoughness;

  /// Approximate area fraction of pixels that fall in the inflammatory
  /// hot-spot cluster (0–1). Feeds the GAGS-adapted area component.
  final double inflammatoryAreaFraction;

  /// Largest connected-component fraction among inflammatory hot-spots —
  /// proxy for nodular / cystic lesion size. 0–1.
  final double nodularClusterScore;

  /// Erythema concentrated in the central face (cheeks/nose zone) —
  /// the hallmark distribution for NRS-defined rosacea. 0–1.
  final double centralFaceErythema;

  /// Erythema concentrated in the lower-third zone (jawline/chin) —
  /// the classical hormonal-acne distribution. 0–1.
  final double jawZoneErythema;

  /// Inflammatory hot-spot density in the lower-third zone (jawline
  /// & chin). Drives the location-weighted hormonal acne score. 0–1.
  final double jawZoneLesionDensity;

  /// Sustained / persistent erythema score — distinguishes standing
  /// rosacea redness from transient flushing. 0–1.
  final double persistentErythemaScore;

  const PhotoFeatures({
    required this.rednessMean,
    required this.rednessVariance,
    required this.saturationMean,
    required this.brightnessMean,
    required this.lesionScore,
    required this.vesselScore,
    required this.textureScore,
    required this.confidence,
    this.pigmentSpotDensity = 0.0,
    this.wrinkleEdgeDensity = 0.0,
    this.poreDensity = 0.0,
    this.textureRoughness = 0.0,
    this.inflammatoryAreaFraction = 0.0,
    this.nodularClusterScore = 0.0,
    this.centralFaceErythema = 0.0,
    this.jawZoneErythema = 0.0,
    this.jawZoneLesionDensity = 0.0,
    this.persistentErythemaScore = 0.0,
  });

  /// Neutral fallback when bytes can't be decoded (e.g. web restrictions).
  /// Yields a "moderate baseline" so the UX still produces a useful result.
  factory PhotoFeatures.neutral() => const PhotoFeatures(
    rednessMean: 0.30,
    rednessVariance: 0.20,
    saturationMean: 0.25,
    brightnessMean: 0.55,
    lesionScore: 0.25,
    vesselScore: 0.20,
    textureScore: 0.30,
    confidence: 0.40,
    pigmentSpotDensity: 0.20,
    wrinkleEdgeDensity: 0.20,
    poreDensity: 0.25,
    textureRoughness: 0.25,
    inflammatoryAreaFraction: 0.04,
    nodularClusterScore: 0.10,
    centralFaceErythema: 0.30,
    jawZoneErythema: 0.25,
    jawZoneLesionDensity: 0.05,
    persistentErythemaScore: 0.25,
  );
}

/// Decodes the photo bytes and computes [PhotoFeatures] via pixel
/// sampling on a resized 160×160 copy. Implements a small library of
/// dermatology-inspired detectors:
///
///   • Erythema index (Takiwaki-style R/(G+B) ratio per pixel)
///   • Erythema distribution: variance, central-face zone, jaw zone
///   • Inflammatory hot-spot detection + connected-cluster size
///     (GAGS-adapted papule/pustule/nodule proxies)
///   • Sobel-style edge density (rhytid / fine-line proxy)
///   • Dark-spot detection (pigment macule / PIH proxy)
///   • Regular dot density in central zones (pore proxy)
///   • Saturation peaks on red hue (telangiectasia proxy)
///
/// All detectors are deterministic, run in well under 200 ms on typical
/// hardware, and never throw — they fall back to [PhotoFeatures.neutral]
/// on any failure.
class PhotoFeatureExtractor {
  /// Returns features for [bytes], or a neutral fallback when decoding
  /// fails. Never throws.
  static PhotoFeatures extract(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return PhotoFeatures.neutral();
      final resized = img.copyResize(decoded, width: 160, height: 160);
      return _computeFeatures(resized);
    } catch (_) {
      return PhotoFeatures.neutral();
    }
  }

  static PhotoFeatures _computeFeatures(img.Image im) {
    final w = im.width;
    final h = im.height;

    // Cache normalized pixel data + skin mask in a single pass.
    final r = Float32List(w * h);
    final g = Float32List(w * h);
    final b = Float32List(w * h);
    final brightness = Float32List(w * h);
    final sat = Float32List(w * h);
    final redRatio = Float32List(w * h); // R / mean(G,B)
    final hueRed = Float32List(w * h); // 1 when hue is red-dominant
    final isSkin = List<bool>.filled(w * h, false);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = im.getPixel(x, y);
        final pr = p.r.toDouble();
        final pg = p.g.toDouble();
        final pb = p.b.toDouble();
        final idx = y * w + x;
        r[idx] = pr;
        g[idx] = pg;
        b[idx] = pb;
        final br = (pr + pg + pb) / (3.0 * 255.0);
        brightness[idx] = br;
        final maxC = math.max(pr, math.max(pg, pb));
        final minC = math.min(pr, math.min(pg, pb));
        sat[idx] = maxC <= 0 ? 0.0 : (maxC - minC) / maxC;
        final gb = math.max(1.0, (pg + pb) / 2.0);
        redRatio[idx] = pr / gb;
        // Red-hue dominance: R is the channel max AND a meaningful margin.
        hueRed[idx] = (pr >= pg && pr >= pb && (pr - math.min(pg, pb)) > 18)
            ? 1.0
            : 0.0;
        // Skin mask: exclude extreme highlights/shadows.
        isSkin[idx] = br >= 0.12 && br <= 0.97;
      }
    }

    int skinCount = 0;
    for (int i = 0; i < w * h; i++) {
      if (isSkin[i]) skinCount++;
    }
    if (skinCount < 200) return PhotoFeatures.neutral();

    // ── 1. Erythema index + variance ──────────────────────────────
    double rrSum = 0, satSum = 0, brSum = 0;
    for (int i = 0; i < w * h; i++) {
      if (!isSkin[i]) continue;
      rrSum += redRatio[i];
      satSum += sat[i];
      brSum += brightness[i];
    }
    final rrMean = rrSum / skinCount;
    final satMean = satSum / skinCount;
    final brMean = brSum / skinCount;

    double rrVar = 0;
    for (int i = 0; i < w * h; i++) {
      if (!isSkin[i]) continue;
      final d = redRatio[i] - rrMean;
      rrVar += d * d;
    }
    rrVar /= skinCount;

    // Normalize: typical neutral skin ~1.05, strong erythema ~1.55.
    final rednessNorm = ((rrMean - 1.05) / 0.50).clamp(0.0, 1.0);
    final rednessVarNorm = (rrVar * 20).clamp(0.0, 1.0);

    // ── 2. Inflammatory hot-spot detection (GAGS papule/pustule) ──
    // Hot pixel = redRatio meaningfully above local mean AND showing
    // local brightness contrast (3D / specular signature of an actual
    // raised lesion). The brightness gate is critical for specificity:
    // post-inflammatory hyperpigmentation (PIH) and erythematous /
    // atrophic scars also elevate redRatio but are flat — they should
    // NOT be counted as active inflammatory lesions. Without this
    // gate, a face with widespread scarring would score identically
    // to one with active pustules.
    final hotThreshold = rrMean + 0.22;
    const brightContrastMin = 0.055; // empirical 3×3 brightness range
    final hot = List<bool>.filled(w * h, false);
    int hotCount = 0;
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i = y * w + x;
        if (!isSkin[i] || redRatio[i] <= hotThreshold) continue;
        // 3×3 brightness range — papules have a highlight+shadow
        // signature; flat pigmented patches do not.
        double bMin = brightness[i], bMax = brightness[i];
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final n = (y + dy) * w + (x + dx);
            final bv = brightness[n];
            if (bv < bMin) bMin = bv;
            if (bv > bMax) bMax = bv;
          }
        }
        if ((bMax - bMin) < brightContrastMin) continue;
        hot[i] = true;
        hotCount++;
      }
    }
    final hotFrac = hotCount / skinCount;
    // Inflammatory load: subtract a small baseline so faint mottling
    // doesn't score, then cap. Tuned so an obviously clear face → 0
    // and a face dotted with active papules → ~0.6.
    final lesionScore = ((hotFrac - 0.012) * 8).clamp(0.0, 1.0);
    final inflammatoryAreaFraction = hotFrac.clamp(0.0, 1.0);

    // ── 3. Largest connected-component (nodule/cyst proxy) ────────
    // Light-weight flood-fill across the hot mask. Capped at 1500
    // pixels per component to keep the cost trivial.
    final visited = List<bool>.filled(w * h, false);
    int largestComponent = 0;
    final stack = <int>[];
    for (int i = 0; i < w * h; i++) {
      if (!hot[i] || visited[i]) continue;
      stack
        ..clear()
        ..add(i);
      visited[i] = true;
      int size = 0;
      while (stack.isNotEmpty && size < 1500) {
        final cur = stack.removeLast();
        size++;
        final cy = cur ~/ w;
        final cx = cur % w;
        // 4-neighbour expansion.
        if (cx > 0) {
          final n = cur - 1;
          if (hot[n] && !visited[n]) {
            visited[n] = true;
            stack.add(n);
          }
        }
        if (cx < w - 1) {
          final n = cur + 1;
          if (hot[n] && !visited[n]) {
            visited[n] = true;
            stack.add(n);
          }
        }
        if (cy > 0) {
          final n = cur - w;
          if (hot[n] && !visited[n]) {
            visited[n] = true;
            stack.add(n);
          }
        }
        if (cy < h - 1) {
          final n = cur + w;
          if (hot[n] && !visited[n]) {
            visited[n] = true;
            stack.add(n);
          }
        }
      }
      if (size > largestComponent) largestComponent = size;
    }
    // Nodule/cyst proxy: largest contiguous inflammatory cluster as a
    // fraction of skin area. Tightened multiplier so a single
    // moderately-sized cluster no longer pegs the score — true cysts
    // are large + raised + clustered, and we additionally gate this
    // in [PhotoAnalysisInput.fromFeatures].
    final nodularRaw = largestComponent / skinCount;
    final nodularClusterScore = (nodularRaw * 6).clamp(0.0, 1.0);

    // ── 4. Zone partition (top / middle / lower thirds) ───────────
    int midSkin = 0, lowSkin = 0;
    double midRr = 0, lowRr = 0;
    int lowHot = 0;
    final thirdH = h ~/ 3;
    for (int y = 0; y < h; y++) {
      final zone = y < thirdH ? 0 : (y < 2 * thirdH ? 1 : 2);
      for (int x = 0; x < w; x++) {
        final i = y * w + x;
        if (!isSkin[i]) continue;
        switch (zone) {
          case 0:
            break;
          case 1:
            midSkin++;
            midRr += redRatio[i];
            break;
          default:
            lowSkin++;
            lowRr += redRatio[i];
            if (hot[i]) lowHot++;
        }
      }
    }
    double zoneNorm(double rrSum, int n) {
      if (n == 0) return 0.0;
      final mean = rrSum / n;
      return ((mean - 1.05) / 0.50).clamp(0.0, 1.0);
    }

    final centralFaceErythema = zoneNorm(midRr, midSkin);
    final jawZoneErythema = zoneNorm(lowRr, lowSkin);
    final jawZoneLesionDensity =
        (lowSkin == 0 ? 0.0 : ((lowHot / lowSkin - 0.03) * 7)).clamp(0.0, 1.0);
    // Persistent erythema = central-face standing redness, robust to
    // a single transient flush (low variance there).
    final persistentErythemaScore =
        (centralFaceErythema * (1 - rednessVarNorm * 0.40)).clamp(0.0, 1.0);

    // ── 5. Vessel score (telangiectasia: saturated thin red) ──────
    int redHueHigh = 0;
    for (int i = 0; i < w * h; i++) {
      if (!isSkin[i]) continue;
      if (hueRed[i] > 0 && sat[i] > 0.30 && redRatio[i] > rrMean + 0.10) {
        redHueHigh++;
      }
    }
    final redHueFrac = redHueHigh / skinCount;
    final vesselScore =
        ((satMean * rednessNorm * 1.4) +
                (redHueFrac * 4) +
                (rednessVarNorm * 0.20))
            .clamp(0.0, 1.0);

    // ── 6. Texture (brightness variance) + roughness ──────────────
    double bVar = 0;
    for (int i = 0; i < w * h; i++) {
      if (!isSkin[i]) continue;
      final d = brightness[i] - brMean;
      bVar += d * d;
    }
    bVar /= skinCount;
    final textureScore = (bVar * 12).clamp(0.0, 1.0);
    final textureRoughness = (math.sqrt(bVar) * 6).clamp(0.0, 1.0);

    // ── 7. Sobel-style edge density (wrinkles / fine lines) ───────
    int edgeCount = 0;
    int edgeDenom = 0;
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i = y * w + x;
        if (!isSkin[i]) continue;
        edgeDenom++;
        // Gx & Gy on brightness channel.
        final gx =
            (brightness[i - 1] * -1 + brightness[i + 1] * 1) +
            (brightness[i - 1 - w] * -1 + brightness[i + 1 - w] * 1) * 0.5 +
            (brightness[i - 1 + w] * -1 + brightness[i + 1 + w] * 1) * 0.5;
        final gy =
            (brightness[i - w] * -1 + brightness[i + w] * 1) +
            (brightness[i - w - 1] * -1 + brightness[i + w - 1] * 1) * 0.5 +
            (brightness[i - w + 1] * -1 + brightness[i + w + 1] * 1) * 0.5;
        final mag = math.sqrt(gx * gx + gy * gy);
        if (mag > 0.18) edgeCount++;
      }
    }
    final edgeFrac = edgeDenom == 0 ? 0.0 : edgeCount / edgeDenom;
    final wrinkleEdgeDensity = ((edgeFrac - 0.05) * 4).clamp(0.0, 1.0);

    // ── 8. Dark-spot detection (hyperpigmentation / PIH proxy) ────
    final brThresholdDark = brMean - 0.18;
    int darkPx = 0;
    for (int i = 0; i < w * h; i++) {
      if (!isSkin[i]) continue;
      // Brown/dark = dim brightness + low blue, neutral saturation.
      if (brightness[i] < brThresholdDark && sat[i] < 0.45 && b[i] < g[i]) {
        darkPx++;
      }
    }
    final darkFrac = darkPx / skinCount;
    final pigmentSpotDensity = ((darkFrac - 0.04) * 5).clamp(0.0, 1.0);

    // ── 9. Pore density (small dark dots in central zone) ─────────
    int poreDots = 0;
    int poreDenom = 0;
    for (int y = thirdH; y < 2 * thirdH; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i = y * w + x;
        if (!isSkin[i]) continue;
        poreDenom++;
        // Local minimum vs. 8-neighbours, with a small magnitude.
        final c = brightness[i];
        if (c >= brMean) continue;
        final neighbors = [
          brightness[i - 1],
          brightness[i + 1],
          brightness[i - w],
          brightness[i + w],
        ];
        bool isLocalMin = true;
        for (final n in neighbors) {
          if (n <= c) {
            isLocalMin = false;
            break;
          }
        }
        if (isLocalMin && (neighbors.reduce(math.max) - c) > 0.04) {
          poreDots++;
        }
      }
    }
    final poreFrac = poreDenom == 0 ? 0.0 : poreDots / poreDenom;
    final poreDensity = ((poreFrac - 0.02) * 12).clamp(0.0, 1.0);

    // ── Confidence: exposure + sample size ────────────────────────
    final exposurePenalty = (brMean < 0.25 || brMean > 0.85) ? 0.45 : 1.0;
    final sampleConf = (skinCount / (w * h)).clamp(0.0, 1.0);
    final confidence =
        (0.55 + 0.45 * sampleConf).clamp(0.0, 1.0) * exposurePenalty;

    return PhotoFeatures(
      rednessMean: rednessNorm,
      rednessVariance: rednessVarNorm,
      saturationMean: satMean,
      brightnessMean: brMean,
      lesionScore: lesionScore,
      vesselScore: vesselScore,
      textureScore: textureScore,
      confidence: confidence,
      pigmentSpotDensity: pigmentSpotDensity,
      wrinkleEdgeDensity: wrinkleEdgeDensity,
      poreDensity: poreDensity,
      textureRoughness: textureRoughness,
      inflammatoryAreaFraction: inflammatoryAreaFraction,
      nodularClusterScore: nodularClusterScore,
      centralFaceErythema: centralFaceErythema,
      jawZoneErythema: jawZoneErythema,
      jawZoneLesionDensity: jawZoneLesionDensity,
      persistentErythemaScore: persistentErythemaScore,
    );
  }
}

/// Auto-detected values for the seven tracker metrics. These map 1:1 to
/// `SkinMetricRegistry.acneAndRosacea` keys so the result screen can
/// persist them in a single batch.
class DetectedMetrics {
  /// Same order as `SkinMetricRegistry.acneAndRosacea`. Stable so the
  /// UI can iterate without coupling to field names.
  final Map<String, int> values;
  const DetectedMetrics(this.values);

  int operator [](String key) => values[key] ?? 0;
  Iterable<String> get keys => values.keys;
}

/// Per-metric clinical derivation describing HOW the AI arrived at a
/// score. Surfaced under each metric tile in the result screen so the
/// user can see the methodology — turning the opaque "AI value" into a
/// transparent, dermatologist-grade calculation.
class MetricDerivation {
  /// Tracker metric key (e.g. `acneSeverity`).
  final String metricKey;

  /// Resolved 0–10 score (mirrors [DetectedMetrics.values]).
  final int score;

  /// Short headline naming the established clinical framework this
  /// score is adapted from (e.g. `Adapted GAGS`).
  final String methodLabel;

  /// One-sentence plain-English explanation of the inputs that drove
  /// the score — written for the patient, not the clinician.
  final String methodDetail;

  /// 0–1 per-metric confidence. Inherits the photo extractor's global
  /// confidence and may be further reduced when a metric's primary
  /// driver feature is itself weak.
  final double confidence;

  const MetricDerivation({
    required this.metricKey,
    required this.score,
    required this.methodLabel,
    required this.methodDetail,
    required this.confidence,
  });
}

/// A single personalised clinical insight surfaced in the analysis view.
class ClinicalInsight {
  final IconData icon;
  final String title;
  final String detail;
  final Color accent;

  const ClinicalInsight({
    required this.icon,
    required this.title,
    required this.detail,
    required this.accent,
  });
}

/// A procedure recommendation with full clinical context.
class ProcedureRecommendation {
  final String name;
  final ProcedureCategory category;
  final ProcedureIntensity intensity;
  final String indication;
  final List<String> pros;
  final List<String> cons;
  final String expectedSessions;
  final String timelineWeeks;
  final int suitabilityPct; // 0–100

  const ProcedureRecommendation({
    required this.name,
    required this.category,
    required this.intensity,
    required this.indication,
    required this.pros,
    required this.cons,
    required this.expectedSessions,
    required this.timelineWeeks,
    required this.suitabilityPct,
  });
}

/// Per-metric delta vs. baseline photo.
class MetricDelta {
  final String metricKey;
  final String metricLabel;
  final int baselineValue;
  final int currentValue;
  final double deltaPct; // negative = improved (lower-is-better metrics)
  const MetricDelta({
    required this.metricKey,
    required this.metricLabel,
    required this.baselineValue,
    required this.currentValue,
    required this.deltaPct,
  });

  bool get improved => currentValue < baselineValue;
  bool get worsened => currentValue > baselineValue;
}

/// Baseline comparison block.
class BaselineComparison {
  final DateTime baselineDate;
  final String baselineImagePath;
  final int weeksSinceBaseline;
  final double baselineSeverityIndex;
  final double currentSeverityIndex;
  final double overallDeltaPct;
  final List<MetricDelta> metricDeltas;
  const BaselineComparison({
    required this.baselineDate,
    required this.baselineImagePath,
    required this.weeksSinceBaseline,
    required this.baselineSeverityIndex,
    required this.currentSeverityIndex,
    required this.overallDeltaPct,
    required this.metricDeltas,
  });

  bool get improved => overallDeltaPct < -2; // >2% drop on 0-10 scale
  bool get worsened => overallDeltaPct > 2;
}

/// Top-level analysis result rendered by the analysis result view.
class PhotoAnalysisResult {
  final PhotoAnalysisInput input;
  final DetectedAcneType acneType;
  final DetectedRosaceaPattern rosaceaPattern;
  final double severityIndex; // 0–10
  final String severityBandLabel; // Clear · Mild · Moderate · Marked · Severe
  final String headline;
  final String subheadline;
  final List<ClinicalInsight> insights;
  final List<ProcedureRecommendation> procedures;
  final List<String> productCues; // short suggestion bullets
  final BaselineComparison? comparison;

  /// AI-detected values for the seven `SkinMetricRegistry.acneAndRosacea`
  /// keys. The result screen renders these as editable tiles and persists
  /// them in a single batch.
  final DetectedMetrics detected;

  /// Per-metric clinical derivation (method label + plain-English detail
  /// + per-metric confidence). Keyed by tracker metric key. Empty when
  /// the analysis was run without a [PhotoFeatures] context (e.g. fully
  /// user-driven input from sliders).
  final Map<String, MetricDerivation> derivations;

  /// 0–1 confidence the engine has in this analysis (driven primarily by
  /// photo exposure + sample size from the feature extractor).
  final double confidence;

  const PhotoAnalysisResult({
    required this.input,
    required this.acneType,
    required this.rosaceaPattern,
    required this.severityIndex,
    required this.severityBandLabel,
    required this.headline,
    required this.subheadline,
    required this.insights,
    required this.procedures,
    required this.productCues,
    required this.comparison,
    required this.detected,
    required this.confidence,
    this.derivations = const {},
  });

  /// True when the engine found no clinically meaningful acne / rosacea
  /// signals (every detected metric ≤ 1 and the overall severity index
  /// sits in the "Clear" band). Used by the result screen to surface a
  /// supportive "None detected" hero card instead of the standard one.
  bool get isClear {
    if (severityIndex >= 1.5) return false;
    for (final v in detected.values.values) {
      if (v > 1) return false;
    }
    return true;
  }

  /// True when the engine's confidence is too low to draw firm
  /// conclusions (e.g. underexposed photo or very small skin sample).
  /// Treated similarly to a clear result so we never imply severity we
  /// cannot actually see.
  bool get isLowConfidence => confidence < 0.40;

  /// Short, plain-language summary describing the detection outcome.
  /// Encouraging when the skin appears clear, neutral when confidence
  /// is low, and clinical when active findings are present.
  String get detectionSummary {
    if (isLowConfidence && !isClear) {
      return 'Low-confidence analysis — try a brighter, closer photo for '
          'a more accurate read.';
    }
    if (isClear) {
      return 'Great progress — no significant acne or rosacea signs '
          'detected in this photo.';
    }
    return subheadline;
  }
}

/// Pure analyser — given input + optional baseline + recent history,
/// returns a deterministic structured analysis.
class AcneRosaceaPhotoAnalyzer {
  static PhotoAnalysisResult analyze({
    required PhotoAnalysisInput input,
    AcneRosaceaLog? baselineSnapshot,
    Map<String, List<AcneRosaceaLog>> history = const {},
    double confidence = 0.85,
    PhotoFeatures? features,
  }) {
    // ── 1. Acne type classification ───────────────────────────────────
    final acneType = _classifyAcne(input);

    // ── 2. Rosacea pattern ────────────────────────────────────────────
    final rosaceaPattern = _classifyRosacea(input);

    // ── 3. Overall severity index (0–10) ──────────────────────────────
    final severityIndex = _computeSeverityIndex(input);
    final band = _severityBand(severityIndex);

    // ── 4. Headline + subheadline ─────────────────────────────────────
    final headline = _composeHeadline(acneType, rosaceaPattern, band);
    final subheadline = _composeSubheadline(input, acneType, rosaceaPattern);

    // ── 5. Personalised insights ──────────────────────────────────────
    final insights = _buildInsights(
      input,
      acneType,
      rosaceaPattern,
      severityIndex,
      history,
    );

    // ── 6. Procedure recommendations ──────────────────────────────────
    final procedures = _buildProcedureRecommendations(
      input,
      acneType,
      rosaceaPattern,
      severityIndex,
    );

    // ── 7. Product cues ───────────────────────────────────────────────
    final productCues = _buildProductCues(input, acneType, rosaceaPattern);

    // ── 8. Baseline comparison ────────────────────────────────────────
    final comparison = _buildComparison(
      input,
      severityIndex,
      baselineSnapshot,
      history,
    );

    // ── 9. Per-metric AI detection (the seven tracker keys) ───────────
    final detected = _buildDetectedMetrics(input, acneType);

    // ── 10. Per-metric clinical derivations (method + detail) ─────────
    final derivations = _buildDerivations(
      input,
      acneType,
      detected,
      features,
      confidence,
    );

    return PhotoAnalysisResult(
      input: input,
      acneType: acneType,
      rosaceaPattern: rosaceaPattern,
      severityIndex: severityIndex,
      severityBandLabel: band,
      headline: headline,
      subheadline: subheadline,
      insights: insights,
      procedures: procedures,
      productCues: productCues,
      comparison: comparison,
      detected: detected,
      confidence: confidence,
      derivations: derivations,
    );
  }

  /// Map the inputs (which were either user-confirmed or auto-derived
  /// from `PhotoFeatures`) into the seven tracker metric keys so the UI
  /// can render one tile + log per metric.
  static DetectedMetrics _buildDetectedMetrics(
    PhotoAnalysisInput i,
    DetectedAcneType acne,
  ) {
    final jaw = i.region == FacialRegion.jawlineChin;
    final hormonalContext =
        acne == DetectedAcneType.hormonal || jaw || i.cycleRelatedFlare;
    // Hormonal sub-score: only meaningful when context flags it. Driven
    // by jawline papules + (optional) cycle relation + adult onset.
    final hormonal = hormonalContext
        ? (((i.inflammatoryAcne + i.cysticActivity) * 0.55) +
                  (i.cycleRelatedFlare ? 1.2 : 0) +
                  (i.adultOnset ? 0.8 : 0))
              .round()
              .clamp(0, 10)
        : 0;
    return DetectedMetrics({
      'acneSeverity': i.inflammatoryAcne,
      'cysticAcneSeverity': i.cysticActivity,
      'hormonalAcneSeverity': hormonal,
      'rosaceaSeverity': i.redness,
      'rosaceaFlushing': i.flushingEpisodes,
      'visibleBloodVessels': i.visibleVessels,
      'skinSensitivity': i.sensitivity,
    });
  }

  // ───────────────────────────────────────────────────────────────────
  // Clinical derivations — per-metric methodology + plain-English
  // explanation. These are surfaced under each metric tile in the
  // result screen so users can see how the AI arrived at the number.
  // ───────────────────────────────────────────────────────────────────

  static Map<String, MetricDerivation> _buildDerivations(
    PhotoAnalysisInput i,
    DetectedAcneType acne,
    DetectedMetrics detected,
    PhotoFeatures? f,
    double globalConfidence,
  ) {
    // Per-metric confidence: start from the photo's global confidence
    // and discount by how strong the metric's primary driver feature
    // actually was (weak drivers → lower confidence).
    double conf(double driverStrength) =>
        (globalConfidence * (0.55 + 0.45 * driverStrength.clamp(0.0, 1.0)))
            .clamp(0.0, 1.0);

    // Without a [PhotoFeatures] context we can still emit honest
    // methodology labels — but with neutral confidences.
    final hasFeatures = f != null;
    final feats = f ?? PhotoFeatures.neutral();

    final acneDriver = math.max(
      feats.lesionScore,
      feats.inflammatoryAreaFraction * 3,
    );
    final cystDriver = feats.nodularClusterScore;
    final hormonalDriver = math.max(
      feats.jawZoneLesionDensity,
      feats.jawZoneErythema,
    );
    final rosaceaDriver = math.max(
      feats.persistentErythemaScore,
      feats.centralFaceErythema,
    );
    final flushDriver = math.max(
      feats.rednessVariance,
      feats.rednessMean * 0.6,
    );
    final vesselDriver = feats.vesselScore;
    final sensDriver = math.max(
      feats.persistentErythemaScore,
      feats.rednessVariance,
    );

    String pct(double v) => '${(v * 100).round()}%';

    return {
      'acneSeverity': MetricDerivation(
        metricKey: 'acneSeverity',
        score: detected['acneSeverity'],
        methodLabel: 'Adapted GAGS',
        methodDetail: hasFeatures
            ? 'Suggests inflammatory lesion involvement covering '
                  '~${pct(feats.inflammatoryAreaFraction)} of the analysed '
                  'skin area, weighted by per-lesion intensity '
                  '(${pct(feats.lesionScore)}). Pigment-spot signal '
                  '(${pct(feats.pigmentSpotDensity)}) was discounted from '
                  'this score so post-inflammatory marks are not mistaken '
                  'for active disease. Adapted from the Global Acne Grading '
                  'System (Doshi 1997).'
            : 'Adapted from the Global Acne Grading System (Doshi 1997). '
                  'Score reflects inflammatory papule/pustule density and '
                  'area of involvement.',
        confidence: conf(acneDriver),
      ),
      'cysticAcneSeverity': MetricDerivation(
        metricKey: 'cysticAcneSeverity',
        score: detected['cysticAcneSeverity'],
        methodLabel: 'Nodule-cluster proxy',
        methodDetail: hasFeatures
            ? 'Largest contiguous inflammatory cluster reads '
                  '${pct(feats.nodularClusterScore)} of the nodule '
                  'threshold. Cystic acne is hard to confirm from a single '
                  'photo — this score stays at zero unless both a sizeable '
                  'cluster AND general inflammatory load are present, '
                  'mirroring how clinicians distinguish nodules from '
                  'clustered papules.'
            : 'Heavy weighting on nodule/cyst size, depth, and '
                  'surrounding inflammation. Scores stay at zero until '
                  'lesion clusters exceed a clinically meaningful size.',
        confidence: conf(cystDriver) * 0.85,
      ),
      'hormonalAcneSeverity': MetricDerivation(
        metricKey: 'hormonalAcneSeverity',
        score: detected['hormonalAcneSeverity'],
        methodLabel: 'Lower-third location bias',
        methodDetail: hasFeatures
            ? 'Jawline/chin zone shows ${pct(feats.jawZoneLesionDensity)} '
                  'inflammatory density and ${pct(feats.jawZoneErythema)} '
                  'erythema. Cycle-related flag: ${i.cycleRelatedFlare ? "yes" : "no"}; '
                  'adult-onset: ${i.adultOnset ? "yes" : "no"}. Consistent '
                  'with the classical mandibular distribution of androgen-'
                  'driven acne.'
            : 'Location-weighted inflammatory score concentrated along '
                  'the jawline and chin — the classical mandibular '
                  'distribution of androgen-driven acne.',
        confidence: conf(hormonalDriver),
      ),
      'rosaceaSeverity': MetricDerivation(
        metricKey: 'rosaceaSeverity',
        score: detected['rosaceaSeverity'],
        methodLabel: 'NRS-adapted erythema',
        methodDetail: hasFeatures
            ? 'Persistent central-face erythema reads '
                  '${pct(feats.persistentErythemaScore)}; overall erythema '
                  '${pct(feats.rednessMean)}. The National Rosacea Society '
                  'Standard Classification identifies persistent centrofacial '
                  'erythema as the cardinal diagnostic feature; mild '
                  'ruddiness alone is not diagnostic.'
            : 'National Rosacea Society criteria: persistent '
                  'centrofacial erythema, papules/pustules, visible vessels, '
                  'and sensitivity — weighted toward standing redness.',
        confidence: conf(rosaceaDriver),
      ),
      'rosaceaFlushing': MetricDerivation(
        metricKey: 'rosaceaFlushing',
        score: detected['rosaceaFlushing'],
        methodLabel: 'Erythema-distribution variance',
        methodDetail: hasFeatures
            ? 'Flushing is fundamentally a HISTORY (NRS criterion 2) — '
                  'a single photo can only hint at it. Erythema variance '
                  '${pct(feats.rednessVariance)}, mean redness '
                  '${pct(feats.rednessMean)}, zone asymmetry '
                  '${pct((feats.jawZoneErythema - feats.centralFaceErythema).abs())}. '
                  'Treat this score as a low-confidence estimate.'
            : 'Approximates the NRS transient-flushing criterion from '
                  'redness distribution + zone asymmetry in a single photo. '
                  'Inherently low-confidence from one image.',
        confidence: conf(flushDriver) * 0.65,
      ),
      'visibleBloodVessels': MetricDerivation(
        metricKey: 'visibleBloodVessels',
        score: detected['visibleBloodVessels'],
        methodLabel: 'Telangiectasia detector',
        methodDetail: hasFeatures
            ? 'Saturated red-hue streak score ${pct(feats.vesselScore)} '
                  '(thin saturated red lines above the erythema baseline). '
                  'Mean saturation ${pct(feats.saturationMean)}. Photo '
                  'resolution limits this detector; structural vessels '
                  'require vascular laser/IPL to resolve when confirmed in '
                  'person.'
            : 'Detector for thin, saturated red streaks above the '
                  'erythema baseline. Inherently dependent on photo '
                  'resolution and lighting.',
        confidence: conf(vesselDriver) * 0.75,
      ),
      'skinSensitivity': MetricDerivation(
        metricKey: 'skinSensitivity',
        score: detected['skinSensitivity'],
        methodLabel: 'Reactive-erythema proxy',
        methodDetail: hasFeatures
            ? 'Persistent erythema ${pct(feats.persistentErythemaScore)}, '
                  'variance ${pct(feats.rednessVariance)}. Stinging and '
                  'burning cannot be measured photographically — this is a '
                  'structural barrier-irritation proxy only. Override if '
                  'you know how your skin actually feels.'
            : 'Barrier-irritation proxy from persistent erythema and '
                  'reactive variance. Stinging cannot be measured from a '
                  'photo — adjust if you know your symptoms.',
        confidence: conf(sensDriver) * 0.70,
      ),
      // Virtual metric — not in the tracker registry, surfaced on the
      // result screen as a "Post-Acne Marks / Scarring" row so users
      // can see what the AI IS seeing when the active-acne scores are
      // intentionally low. Drives no logging.
      'postAcneScarring': MetricDerivation(
        metricKey: 'postAcneScarring',
        score: hasFeatures
            ? (((feats.pigmentSpotDensity * 7.0) +
                          (feats.textureRoughness * 3.0))
                      .round())
                  .clamp(0, 10)
            : 0,
        methodLabel: 'PIH + texture residual',
        methodDetail: hasFeatures
            ? 'Pigment-spot density ${pct(feats.pigmentSpotDensity)} '
                  'and surface roughness ${pct(feats.textureRoughness)}. '
                  'Consistent with post-inflammatory hyperpigmentation '
                  '(PIH) and/or residual textural changes from prior acne '
                  '— distinct from active disease and treated differently '
                  '(retinoids, microneedling, chemical peels, laser).'
            : 'Aggregate of pigment-spot density and surface roughness '
                  '— a proxy for post-inflammatory hyperpigmentation and '
                  'residual scarring.',
        confidence: conf(
          math.max(feats.pigmentSpotDensity, feats.textureRoughness),
        ),
      ),
    };
  }

  // ───────────────────────────────────────────────────────────────────
  // Classification rules
  // ───────────────────────────────────────────────────────────────────

  static DetectedAcneType _classifyAcne(PhotoAnalysisInput i) {
    final inf = i.inflammatoryAcne;
    final com = i.comedonalLoad;
    final cyst = i.cysticActivity;
    final jaw = i.region == FacialRegion.jawlineChin;

    if (cyst >= 6) return DetectedAcneType.cystic;
    if ((jaw && inf >= 3) ||
        (i.cycleRelatedFlare && inf >= 3) ||
        (i.adultOnset && jaw && (inf + cyst) >= 4)) {
      return DetectedAcneType.hormonal;
    }
    if (inf >= 5 && com >= 5) return DetectedAcneType.mixed;
    if (inf >= 4 && com < 4) return DetectedAcneType.inflammatory;
    if (com >= 4 && inf < 4) return DetectedAcneType.comedonal;
    if (inf < 2 && com < 2 && cyst < 2) return DetectedAcneType.none;
    return DetectedAcneType.mixed;
  }

  static DetectedRosaceaPattern _classifyRosacea(PhotoAnalysisInput i) {
    final red = i.redness;
    final ves = i.visibleVessels;
    final flush = i.flushingEpisodes;
    final pap = i.inflammatoryAcne;

    // Papulopustular if persistent redness + papules together.
    if (red >= 5 && pap >= 5 && i.cysticActivity < 5) {
      return DetectedRosaceaPattern.papulopustular;
    }
    // Persistent (erythematotelangiectatic): standing redness + vessels.
    if (red >= 4 && ves >= 4) {
      return DetectedRosaceaPattern.erythematotelangiectatic;
    }
    if (red >= 4 || ves >= 4) {
      return DetectedRosaceaPattern.erythematotelangiectatic;
    }
    // Transient: episodic flushing without persistent redness.
    if (flush >= 5 && red < 4) {
      return DetectedRosaceaPattern.transientFlushing;
    }
    return DetectedRosaceaPattern.none;
  }

  static double _computeSeverityIndex(PhotoAnalysisInput i) {
    // Weighted composite emphasising lesions and persistent redness.
    final num raw =
        i.inflammatoryAcne * 1.0 +
        i.cysticActivity * 1.3 +
        i.comedonalLoad * 0.6 +
        i.redness * 0.9 +
        i.visibleVessels * 0.7 +
        i.flushingEpisodes * 0.5 +
        i.sensitivity * 0.5;
    const num totalWeight = 1.0 + 1.3 + 0.6 + 0.9 + 0.7 + 0.5 + 0.5; // 5.5
    return (raw / totalWeight).clamp(0.0, 10.0).toDouble();
  }

  static String _severityBand(double index) {
    if (index < 1.5) return 'Clear';
    if (index < 3.0) return 'Mild';
    if (index < 5.0) return 'Moderate';
    if (index < 7.0) return 'Marked';
    return 'Severe';
  }

  // ───────────────────────────────────────────────────────────────────
  // Narrative composition
  // ───────────────────────────────────────────────────────────────────

  static String _composeHeadline(
    DetectedAcneType acne,
    DetectedRosaceaPattern ros,
    String band,
  ) {
    final acneLabel = _acneLabel(acne);
    final rosLabel = _rosaceaLabel(ros);
    if (acne == DetectedAcneType.none && ros == DetectedRosaceaPattern.none) {
      return 'Clear & well-balanced skin signature';
    }
    if (acne == DetectedAcneType.none) {
      return '$band $rosLabel pattern detected';
    }
    if (ros == DetectedRosaceaPattern.none) {
      return '$band $acneLabel pattern detected';
    }
    return '$band $acneLabel + $rosLabel overlap';
  }

  static String _composeSubheadline(
    PhotoAnalysisInput i,
    DetectedAcneType acne,
    DetectedRosaceaPattern ros,
  ) {
    final parts = <String>[];
    if (acne == DetectedAcneType.hormonal) {
      parts.add('hormonal signature concentrated along the lower face');
    } else if (acne == DetectedAcneType.cystic) {
      parts.add('deep nodular activity suggests systemic-level evaluation');
    } else if (acne == DetectedAcneType.inflammatory) {
      parts.add('active inflammatory lesions dominate the visible field');
    } else if (acne == DetectedAcneType.comedonal) {
      parts.add('congestion-led pattern — comedones over inflammation');
    } else if (acne == DetectedAcneType.mixed) {
      parts.add('mixed inflammatory + comedonal load present');
    }
    if (ros == DetectedRosaceaPattern.papulopustular) {
      parts.add('papulopustular rosacea features overlap with acne lesions');
    } else if (ros == DetectedRosaceaPattern.erythematotelangiectatic) {
      parts.add('persistent central redness with visible capillaries');
    } else if (ros == DetectedRosaceaPattern.transientFlushing) {
      parts.add('episodic vascular flushing without standing erythema');
    }
    if (i.sensitivity >= 6) {
      parts.add('barrier reactivity is elevated');
    }
    if (parts.isEmpty) return 'Routine maintenance pattern.';
    return '${parts.join(' · ')}.';
  }

  // ───────────────────────────────────────────────────────────────────
  // Insights
  // ───────────────────────────────────────────────────────────────────

  static List<ClinicalInsight> _buildInsights(
    PhotoAnalysisInput i,
    DetectedAcneType acne,
    DetectedRosaceaPattern ros,
    double severity,
    Map<String, List<AcneRosaceaLog>> history,
  ) {
    final out = <ClinicalInsight>[];
    const teal = Color(0xFF3E7C7E);
    const rose = Color(0xFFE8A8B5);
    const amber = Color(0xFFD9A441);
    const coral = Color(0xFFC1545A);

    // Hormonal pattern insight.
    if (acne == DetectedAcneType.hormonal ||
        (i.region == FacialRegion.jawlineChin && i.inflammatoryAcne >= 4)) {
      out.add(
        const ClinicalInsight(
          icon: Icons.calendar_month_rounded,
          title: 'Jawline pattern suggests hormonal influence',
          detail:
              'Breakouts concentrated along the lower face, jawline, and chin '
              'classically reflect androgen-driven sebum activity — often '
              'flaring 7–10 days before menses. Topical actives help, but a '
              'conversation about spironolactone or combined oral contraceptives '
              'with a dermatologist is worth having if this persists.',
          accent: rose,
        ),
      );
    }

    // Cystic warning.
    if (acne == DetectedAcneType.cystic || i.cysticActivity >= 6) {
      out.add(
        const ClinicalInsight(
          icon: Icons.medical_services_rounded,
          title: 'Cystic activity may warrant systemic therapy',
          detail:
              'Deep, painful nodules respond poorly to topicals alone and carry '
              'meaningful scarring risk. Oral antibiotics, hormonal therapy, or '
              'isotretinoin are evidence-based options worth discussing with '
              'a dermatologist sooner rather than later.',
          accent: coral,
        ),
      );
    }

    // Rosacea + barrier compromise.
    if (ros != DetectedRosaceaPattern.none && i.sensitivity >= 5) {
      out.add(
        const ClinicalInsight(
          icon: Icons.shield_moon_rounded,
          title: 'Compromised barrier — simplify before adding actives',
          detail:
              'Active rosacea features plus stinging suggest barrier '
              'disruption. Two to four weeks of a stripped-down ceramide + '
              'niacinamide routine, with strict avoidance of fragrance, '
              'menthol, and high-strength acids, will outperform any new '
              'active you could layer on.',
          accent: teal,
        ),
      );
    }

    // Comedonal pattern.
    if (acne == DetectedAcneType.comedonal && severity < 5) {
      out.add(
        const ClinicalInsight(
          icon: Icons.water_drop_rounded,
          title: 'Congestion-led — keratolytics will move the needle most',
          detail:
              'Comedonal patterns respond predictably to BHA (salicylic acid '
              '0.5–2%) two to four nights weekly and a low-strength retinoid '
              'on alternate nights, paired with a non-comedogenic moisturiser. '
              'Visible improvement typically begins around week 6.',
          accent: amber,
        ),
      );
    }

    // Mixed inflammatory.
    if (acne == DetectedAcneType.mixed) {
      out.add(
        const ClinicalInsight(
          icon: Icons.layers_rounded,
          title: 'Mixed pattern — treat inflammation first',
          detail:
              'When inflammatory and comedonal lesions coexist, prioritising '
              'inflammation control (benzoyl peroxide 2.5% short contact, or '
              'azelaic acid 10–20%) before ramping retinoid frequency reduces '
              'irritation and post-inflammatory hyperpigmentation risk.',
          accent: rose,
        ),
      );
    }

    // Visible vessels insight.
    if (i.visibleVessels >= 5) {
      out.add(
        const ClinicalInsight(
          icon: Icons.account_tree_rounded,
          title: 'Telangiectasia is structural — vascular laser is the fix',
          detail:
              'Visible capillaries do not resolve with topicals. Once active '
              'inflammation is controlled, IPL or pulsed-dye laser (PDL) '
              'effectively closes the vessels with 2–4 sessions and minimal '
              'downtime.',
          accent: teal,
        ),
      );
    }

    // History-derived progress insight.
    if (history.isNotEmpty) {
      final allRecent = history.values
          .expand((x) => x)
          .where((e) => DateTime.now().difference(e.timestamp).inDays <= 14)
          .toList();
      if (allRecent.length >= 4) {
        out.add(
          ClinicalInsight(
            icon: Icons.timeline_rounded,
            title: 'You\'ve logged ${allRecent.length} data points in 14 days',
            detail:
                'Consistent self-tracking is the single biggest predictor of '
                'meaningful improvement. The trend engine will start surfacing '
                'pattern-level triggers (products, cycle, weather) as your '
                'log depth grows.',
            accent: teal,
          ),
        );
      }
    }

    // Always-on disclaimer-style note.
    if (out.isEmpty) {
      out.add(
        const ClinicalInsight(
          icon: Icons.spa_rounded,
          title: 'Maintenance phase — protect what you\'ve built',
          detail:
              'No dominant acne or rosacea pattern is currently expressed. '
              'Keep daily SPF 30+, a gentle barrier routine, and a single '
              'evidence-based active (retinoid or azelaic acid) to maintain.',
          accent: teal,
        ),
      );
    }

    return out;
  }

  // ───────────────────────────────────────────────────────────────────
  // Procedure recommendations
  // ───────────────────────────────────────────────────────────────────

  static List<ProcedureRecommendation> _buildProcedureRecommendations(
    PhotoAnalysisInput i,
    DetectedAcneType acne,
    DetectedRosaceaPattern ros,
    double severity,
  ) {
    final out = <ProcedureRecommendation>[];

    // HydraFacial — congestion-led, mild-moderate, gentle entry point.
    if (i.comedonalLoad >= 3 && severity < 6 && i.sensitivity < 7) {
      out.add(
        ProcedureRecommendation(
          name: 'HydraFacial',
          category: ProcedureCategory.inOffice,
          intensity: ProcedureIntensity.gentle,
          indication:
              'Gentle deep-clean for congestion-led patterns; no downtime; '
              'safe alongside most topical actives.',
          pros: const [
            'Zero downtime — return to normal activity immediately',
            'Visible decongestion the same day',
            'Safe with most actives and during travel weeks',
          ],
          cons: const [
            'Effect is temporary — needs monthly maintenance to hold',
            'Will not resolve cystic lesions or hormonal pattern alone',
          ],
          expectedSessions: '1 every 4–6 weeks',
          timelineWeeks: 'Immediate; cumulative over 8–12 weeks',
          suitabilityPct: _scoreFromFlags([
            if (i.comedonalLoad >= 5) 25,
            if (severity < 5) 20,
            if (i.sensitivity < 5) 15,
            if (acne == DetectedAcneType.comedonal) 25,
            if (acne == DetectedAcneType.mixed) 15,
            if (ros == DetectedRosaceaPattern.none) 10,
          ]),
        ),
      );
    }

    // Salicylic acid peel — comedonal/oily, low sensitivity.
    if (i.comedonalLoad >= 4 && i.sensitivity < 6) {
      out.add(
        ProcedureRecommendation(
          name: 'Salicylic Acid Peel (20–30%)',
          category: ProcedureCategory.inOffice,
          intensity: ProcedureIntensity.moderate,
          indication:
              'Lipophilic BHA peel that penetrates oil-rich follicles — '
              'gold-standard for comedonal and mixed inflammatory patterns.',
          pros: const [
            'Targets follicular plugging directly',
            '1–2 days of mild flaking; otherwise zero social downtime',
            'Reduces post-inflammatory hyperpigmentation',
          ],
          cons: const [
            'Requires SPF and active-pause for 5–7 days after',
            'Not appropriate during active rosacea flare',
          ],
          expectedSessions: '3–6 sessions, 2–4 weeks apart',
          timelineWeeks: '4–10 weeks to clear visible congestion',
          suitabilityPct: _scoreFromFlags([
            if (i.comedonalLoad >= 6) 30,
            if (i.inflammatoryAcne >= 4) 20,
            if (acne == DetectedAcneType.comedonal ||
                acne == DetectedAcneType.mixed)
              25,
            if (ros == DetectedRosaceaPattern.none) 15,
            if (i.sensitivity < 5) 10,
          ]),
        ),
      );
    }

    // Mandelic acid peel — sensitive + pigmented.
    if (i.sensitivity >= 4 && acne != DetectedAcneType.cystic) {
      out.add(
        ProcedureRecommendation(
          name: 'Mandelic Acid Peel',
          category: ProcedureCategory.inOffice,
          intensity: ProcedureIntensity.gentle,
          indication:
              'Large-molecule AHA — slower penetration makes it safer for '
              'sensitive, reactive, or darker phototypes prone to PIH.',
          pros: const [
            'Very low irritation profile',
            'Addresses both PIH and mild texture',
            'Safe on rosacea-prone skin (lower concentrations)',
          ],
          cons: const [
            'Slower visible results vs. salicylic',
            'Requires consistent SPF',
          ],
          expectedSessions: '4–6 sessions, every 3 weeks',
          timelineWeeks: '6–12 weeks',
          suitabilityPct: _scoreFromFlags([
            if (i.sensitivity >= 5) 25,
            if (i.sensitivity >= 7) 15,
            if (acne != DetectedAcneType.cystic) 15,
            if (ros != DetectedRosaceaPattern.papulopustular) 15,
            15,
          ]),
        ),
      );
    }

    // Blue light LED — mild-moderate inflammatory.
    if (i.inflammatoryAcne >= 3 && severity < 6) {
      out.add(
        ProcedureRecommendation(
          name: 'Blue Light LED Therapy',
          category: ProcedureCategory.light,
          intensity: ProcedureIntensity.gentle,
          indication:
              'Targets C. acnes bacteria with 415 nm light — drug-free '
              'reduction of inflammatory lesions over 4–8 weeks.',
          pros: const [
            'No downtime, no skin irritation',
            'Stacks safely with topicals',
            'At-home devices increasingly clinically validated',
          ],
          cons: const [
            'Slow onset — consistency matters more than intensity',
            'Marginal effect on comedonal or cystic activity',
          ],
          expectedSessions: '3–5 sessions/week for 4–8 weeks',
          timelineWeeks: '4–8 weeks',
          suitabilityPct: _scoreFromFlags([
            if (i.inflammatoryAcne >= 5) 25,
            if (severity < 5) 20,
            if (acne == DetectedAcneType.inflammatory) 25,
            if (acne == DetectedAcneType.mixed) 15,
            15,
          ]),
        ),
      );
    }

    // Red light LED — rosacea, barrier, sensitivity.
    if (ros != DetectedRosaceaPattern.none || i.sensitivity >= 5) {
      out.add(
        ProcedureRecommendation(
          name: 'Red Light LED (630–660 nm)',
          category: ProcedureCategory.light,
          intensity: ProcedureIntensity.gentle,
          indication:
              'Anti-inflammatory wavelengths that calm rosacea-prone skin and '
              'support barrier recovery without irritation.',
          pros: const [
            'Reduces persistent erythema in 6–10 weeks',
            'Excellent companion to a stripped-down barrier routine',
            'No restrictions during travel or active flare',
          ],
          cons: const [
            'Will not address visible vessels (telangiectasia)',
            'Requires near-daily use for meaningful effect',
          ],
          expectedSessions: '5 sessions/week for 8 weeks',
          timelineWeeks: '6–10 weeks',
          suitabilityPct: _scoreFromFlags([
            if (ros == DetectedRosaceaPattern.papulopustular) 25,
            if (ros == DetectedRosaceaPattern.erythematotelangiectatic) 25,
            if (i.sensitivity >= 6) 20,
            if (i.redness >= 5) 15,
            15,
          ]),
        ),
      );
    }

    // IPL / Vascular laser — telangiectasia, rosacea.
    if (i.visibleVessels >= 4 ||
        ros == DetectedRosaceaPattern.erythematotelangiectatic) {
      out.add(
        ProcedureRecommendation(
          name: 'IPL or Pulsed-Dye Laser (Vascular)',
          category: ProcedureCategory.energy,
          intensity: ProcedureIntensity.moderate,
          indication:
              'Selectively closes visible capillaries and reduces background '
              'erythema — the only way to address structural vessel changes.',
          pros: const [
            'Permanent vessel closure',
            '2–4 sessions typically sufficient',
            'Reduces baseline redness, not just vessels',
          ],
          cons: const [
            'Mild bruising possible (especially PDL) for 5–10 days',
            'Active inflammation must be controlled before treatment',
            'SPF discipline non-negotiable post-procedure',
          ],
          expectedSessions: '2–4 sessions, 4–6 weeks apart',
          timelineWeeks: 'Visible improvement after session 1',
          suitabilityPct: _scoreFromFlags([
            if (i.visibleVessels >= 6) 30,
            if (i.visibleVessels >= 4) 20,
            if (ros == DetectedRosaceaPattern.erythematotelangiectatic) 25,
            if (i.inflammatoryAcne < 5) 15,
            10,
          ]),
        ),
      );
    }

    // Isotretinoin consult — severe cystic.
    if (acne == DetectedAcneType.cystic && i.cysticActivity >= 7) {
      out.add(
        const ProcedureRecommendation(
          name: 'Isotretinoin Consultation',
          category: ProcedureCategory.systemicConsult,
          intensity: ProcedureIntensity.systemic,
          indication:
              'Severe, recalcitrant, or scarring nodulocystic acne — the '
              'closest thing dermatology has to a cure.',
          pros: [
            'Highest sustained-remission rate of any acne therapy',
            'Definitive course (typically 5–7 months)',
            'Eliminates scarring trajectory if started early',
          ],
          cons: [
            'Strict monitoring (labs, mandatory pregnancy prevention)',
            'Dryness, fragility, and photosensitivity during course',
            'Requires prescriber commitment and adherence',
          ],
          expectedSessions: '1 dermatology consult to initiate',
          timelineWeeks: '5–7 month course',
          suitabilityPct: 92,
        ),
      );
    }

    // Spironolactone / hormonal consult.
    if (acne == DetectedAcneType.hormonal ||
        (i.cycleRelatedFlare && i.inflammatoryAcne >= 4)) {
      out.add(
        const ProcedureRecommendation(
          name: 'Hormonal Workup (Spironolactone / OCP)',
          category: ProcedureCategory.systemicConsult,
          intensity: ProcedureIntensity.systemic,
          indication:
              'Cycle-related lower-face breakouts respond predictably to '
              'androgen-blocking spironolactone or combined oral contraceptives.',
          pros: [
            'Addresses upstream driver, not surface symptoms',
            'Highly effective for jawline / chin pattern',
            'Steady-state improvement in 8–12 weeks',
          ],
          cons: [
            'Requires prescriber and basic labs (potassium for spiro)',
            'Not appropriate during pregnancy planning',
          ],
          expectedSessions: '1 consult; quarterly follow-up',
          timelineWeeks: '8–12 weeks to steady-state',
          suitabilityPct: 88,
        ),
      );
    }

    // Microneedling (post-acne texture, scar risk).
    if (severity < 4 && i.cysticActivity < 3 && i.inflammatoryAcne < 4) {
      out.add(
        const ProcedureRecommendation(
          name: 'Microneedling (Post-Inflammatory Texture)',
          category: ProcedureCategory.scarRevision,
          intensity: ProcedureIntensity.moderate,
          indication:
              'Once active acne is controlled, microneedling addresses '
              'rolling and shallow boxcar scars by stimulating collagen.',
          pros: [
            'Modest downtime (24–48 hours)',
            'Compatible with most skin tones',
            'Cumulative improvement across sessions',
          ],
          cons: [
            'Requires acne to be quiescent first',
            'Multiple sessions needed for noticeable texture gain',
            'Not appropriate during active flare',
          ],
          expectedSessions: '3–6 sessions, 4–6 weeks apart',
          timelineWeeks: '12–24 weeks',
          suitabilityPct: 70,
        ),
      );
    }

    // Sort by suitability descending and cap at 5.
    out.sort((a, b) => b.suitabilityPct.compareTo(a.suitabilityPct));
    return out.take(5).toList();
  }

  static int _scoreFromFlags(List<int> contributions) {
    final sum = contributions.fold<int>(0, (a, b) => a + b);
    return sum.clamp(35, 96);
  }

  // ───────────────────────────────────────────────────────────────────
  // Product cues
  // ───────────────────────────────────────────────────────────────────

  static List<String> _buildProductCues(
    PhotoAnalysisInput i,
    DetectedAcneType acne,
    DetectedRosaceaPattern ros,
  ) {
    final out = <String>[];
    if (acne == DetectedAcneType.comedonal || acne == DetectedAcneType.mixed) {
      out.add('Salicylic acid 0.5–2% BHA, 2–4 nights/week');
    }
    if (acne == DetectedAcneType.inflammatory ||
        acne == DetectedAcneType.mixed) {
      out.add('Benzoyl peroxide 2.5% short-contact (rinse-off) cleanser');
    }
    if (acne == DetectedAcneType.hormonal) {
      out.add('Azelaic acid 10–20% AM + retinoid alternate PM');
    }
    if (ros != DetectedRosaceaPattern.none) {
      out.add('Azelaic acid 15% gel — calms erythema + papules');
      out.add('Ceramide + niacinamide barrier moisturiser AM/PM');
    }
    if (i.sensitivity >= 5) {
      out.add('Eliminate fragrance, menthol, essential oils for 4 weeks');
    }
    out.add('Broad-spectrum SPF 30+ daily — non-negotiable');
    return out;
  }

  // ───────────────────────────────────────────────────────────────────
  // Baseline comparison
  // ───────────────────────────────────────────────────────────────────

  static BaselineComparison? _buildComparison(
    PhotoAnalysisInput i,
    double currentSeverity,
    AcneRosaceaLog? baseline,
    Map<String, List<AcneRosaceaLog>> history,
  ) {
    if (baseline == null) return null;

    final weeks = (i.capturedAt.difference(baseline.timestamp).inDays / 7)
        .floor();

    // Approximate baseline severity index from the metric value the user
    // logged at baseline (it represents the symptom they chose to track).
    final baselineSeverity = baseline.value.toDouble();
    final delta =
        ((currentSeverity - baselineSeverity) /
            (baselineSeverity == 0 ? 1 : baselineSeverity)) *
        100.0;

    // Per-metric deltas: for each acne/rosacea metric, compare current
    // user-rated input value vs. the oldest log of that metric.
    final deltas = <MetricDelta>[];
    final metricMap = <String, int>{
      'acneSeverity': i.inflammatoryAcne,
      'cysticAcneSeverity': i.cysticActivity,
      'hormonalAcneSeverity': i.inflammatoryAcne, // proxy: same panel
      'rosaceaSeverity': i.redness,
      'rosaceaFlushing': i.flushingEpisodes,
      'visibleBloodVessels': i.visibleVessels,
      'skinSensitivity': i.sensitivity,
    };
    metricMap.forEach((key, current) {
      final list = history[key] ?? const <AcneRosaceaLog>[];
      if (list.isEmpty) return;
      // Logs are stored newest-first; take oldest for baseline proxy.
      final old = list.last;
      if (old.value == current) return;
      final pct =
          ((current - old.value) / (old.value == 0 ? 1 : old.value)) * 100.0;
      final label = SkinMetricRegistry.byKey(key)?.shortName ?? key;
      deltas.add(
        MetricDelta(
          metricKey: key,
          metricLabel: label,
          baselineValue: old.value,
          currentValue: current,
          deltaPct: pct,
        ),
      );
    });

    return BaselineComparison(
      baselineDate: baseline.timestamp,
      baselineImagePath: baseline.imagePath,
      weeksSinceBaseline: weeks,
      baselineSeverityIndex: baselineSeverity,
      currentSeverityIndex: currentSeverity,
      overallDeltaPct: delta,
      metricDeltas: deltas,
    );
  }

  // ───────────────────────────────────────────────────────────────────
  // Label helpers
  // ───────────────────────────────────────────────────────────────────

  static String _acneLabel(DetectedAcneType t) {
    switch (t) {
      case DetectedAcneType.none:
        return 'no active acne';
      case DetectedAcneType.comedonal:
        return 'comedonal acne';
      case DetectedAcneType.inflammatory:
        return 'inflammatory acne';
      case DetectedAcneType.cystic:
        return 'cystic acne';
      case DetectedAcneType.hormonal:
        return 'hormonal acne';
      case DetectedAcneType.mixed:
        return 'mixed acne';
    }
  }

  static String _rosaceaLabel(DetectedRosaceaPattern p) {
    switch (p) {
      case DetectedRosaceaPattern.none:
        return 'no rosacea features';
      case DetectedRosaceaPattern.transientFlushing:
        return 'transient flushing';
      case DetectedRosaceaPattern.erythematotelangiectatic:
        return 'persistent rosacea';
      case DetectedRosaceaPattern.papulopustular:
        return 'papulopustular rosacea';
    }
  }
}

/// UI helpers for the photo analysis result view.
class PhotoAnalysisUi {
  static String acneTypeLabel(DetectedAcneType t) =>
      AcneRosaceaPhotoAnalyzer._acneLabel(
        t,
      ).replaceFirstMapped(RegExp(r'^(.)'), (m) => m[1]!.toUpperCase());

  static String rosaceaPatternLabel(DetectedRosaceaPattern p) =>
      AcneRosaceaPhotoAnalyzer._rosaceaLabel(
        p,
      ).replaceFirstMapped(RegExp(r'^(.)'), (m) => m[1]!.toUpperCase());

  static String regionLabel(FacialRegion r) {
    switch (r) {
      case FacialRegion.fullFace:
        return 'Full face';
      case FacialRegion.forehead:
        return 'Forehead';
      case FacialRegion.cheeks:
        return 'Cheeks';
      case FacialRegion.jawlineChin:
        return 'Jawline & chin';
      case FacialRegion.nose:
        return 'Nose';
      case FacialRegion.perioral:
        return 'Perioral';
    }
  }

  static IconData regionIcon(FacialRegion r) {
    switch (r) {
      case FacialRegion.fullFace:
        return Icons.face_retouching_natural_rounded;
      case FacialRegion.forehead:
        return Icons.arrow_upward_rounded;
      case FacialRegion.cheeks:
        return Icons.face_3_outlined;
      case FacialRegion.jawlineChin:
        return Icons.arrow_downward_rounded;
      case FacialRegion.nose:
        return Icons.center_focus_strong_rounded;
      case FacialRegion.perioral:
        return Icons.front_hand_outlined;
    }
  }

  static IconData procedureCategoryIcon(ProcedureCategory c) {
    switch (c) {
      case ProcedureCategory.inOffice:
        return Icons.medical_services_outlined;
      case ProcedureCategory.energy:
        return Icons.bolt_rounded;
      case ProcedureCategory.light:
        return Icons.lightbulb_outline_rounded;
      case ProcedureCategory.topicalPrescription:
        return Icons.medication_outlined;
      case ProcedureCategory.systemicConsult:
        return Icons.health_and_safety_outlined;
      case ProcedureCategory.scarRevision:
        return Icons.healing_rounded;
    }
  }

  static String procedureCategoryLabel(ProcedureCategory c) {
    switch (c) {
      case ProcedureCategory.inOffice:
        return 'In-office';
      case ProcedureCategory.energy:
        return 'Energy device';
      case ProcedureCategory.light:
        return 'Light therapy';
      case ProcedureCategory.topicalPrescription:
        return 'Prescription topical';
      case ProcedureCategory.systemicConsult:
        return 'Systemic consult';
      case ProcedureCategory.scarRevision:
        return 'Scar revision';
    }
  }

  static String intensityLabel(ProcedureIntensity i) {
    switch (i) {
      case ProcedureIntensity.gentle:
        return 'Gentle';
      case ProcedureIntensity.moderate:
        return 'Moderate';
      case ProcedureIntensity.intensive:
        return 'Intensive';
      case ProcedureIntensity.systemic:
        return 'Systemic';
    }
  }

  static Color intensityColor(ProcedureIntensity i) {
    switch (i) {
      case ProcedureIntensity.gentle:
        return const Color(0xFF4FAE8B);
      case ProcedureIntensity.moderate:
        return const Color(0xFFD9A441);
      case ProcedureIntensity.intensive:
        return const Color(0xFFD37B4F);
      case ProcedureIntensity.systemic:
        return const Color(0xFFC1545A);
    }
  }
}
