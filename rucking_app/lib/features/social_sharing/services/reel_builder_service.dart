import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Builds a vertical MP4 reel from one or more images.
/// - No audio track (Instagram lets users add music in-app)
/// - 1080x1920, 30fps, H.264 + yuv420p for broad compatibility
class ReelBuilderService {
  const ReelBuilderService();

  /// Build a reel from [imagePaths]. Returns the output MP4 path.
  Future<String> buildReel(
    List<String> imagePaths, {
    int width = 1080,
    int height = 1920,
    int fps = 30,
    double clipSeconds = 2.5,
    double transitionSeconds = 0.5,
  }) async {
    if (imagePaths.isEmpty) {
      throw ArgumentError('No images provided');
    }

    final tmpDir = await getTemporaryDirectory();
    final reelsDir = Directory(p.join(tmpDir.path, 'reels'));
    if (!reelsDir.existsSync()) reelsDir.createSync(recursive: true);
    final outPath = p.join(
      reelsDir.path,
      'reel_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );

    // Build inputs: loop each still image for clipSeconds
    final inputs = <String>[];
    for (final img in imagePaths) {
      // -r sets a nominal rate for the looped input
      inputs.add("-loop 1 -t ${clipSeconds.toStringAsFixed(3)} -r $fps -i \"${img}\"");
    }

    // Per-stream processing: scale to cover and apply a gentle Ken Burns where feasible.
    // Use alternating zoom-in/out to add subtle motion.
    final frames = (fps * clipSeconds).round();
    final procLabels = <String>[];
    final procClauses = <String>[];
    for (var i = 0; i < imagePaths.length; i++) {
      final labelIn = '[$i:v]';
      final labelOut = '[v$i]';
      procLabels.add(labelOut);

      // Zoom formula: ramp between 1.0 and 1.08 over the clip.
      // If zoompan fails on some devices, the filter chain still scales/pads.
      final zoomStart = (i % 2 == 0) ? 1.0 : 1.08; // even: zoom in; odd: zoom out
      final zoomEnd = (i % 2 == 0) ? 1.08 : 1.0;
      final zoomRate = (zoomEnd - zoomStart) / (frames == 0 ? 1 : frames);

      final clause = StringBuffer()
        ..write(labelIn)
        ..write(
            'scale=${width}:${height}:force_original_aspect_ratio=cover,setsar=1,')
        ..write(
            "zoompan=z='if(eq(on,0),${zoomStart.toStringAsFixed(3)},min(max(pzoom,${zoomStart.toStringAsFixed(3)})+${zoomRate.toStringAsFixed(5)},${zoomEnd.toStringAsFixed(3)}))':d=${frames}:s=${width}x${height}:fps=${fps},")
        ..write('format=yuv420p')
        ..write(labelOut)
        ..write(';');

      procClauses.add(clause.toString());
    }

    // Chain crossfades
    String resultLabel = procLabels.first;
    double accDuration = clipSeconds; // duration so far
    final xfadeClauses = <String>[];
    for (var i = 1; i < procLabels.length; i++) {
      final next = procLabels[i];
      final offset = (accDuration - transitionSeconds);
      final out = '[x$i]';
      xfadeClauses.add(
          '$resultLabel$next xfade=transition=fade:duration=${transitionSeconds.toStringAsFixed(3)}:offset=${offset.toStringAsFixed(3)} $out;');
      resultLabel = out;
      accDuration = accDuration + clipSeconds - transitionSeconds;
    }

    final filter = (procClauses + xfadeClauses).join();

    // Assemble command
    final cmd = StringBuffer()
      ..write(inputs.join(' '))
      ..write(' -filter_complex "')
      ..write(filter)
      ..write('" ')
      ..write('-map "${resultLabel}" ')
      ..write('-c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p ')
      ..write('-movflags +faststart -an ')
      ..write('"$outPath"');

    // Execute
    final session = await FFmpegKit.execute(cmd.toString());
    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc)) {
      return outPath;
    }

    // Fallback: simple hard cuts without zoom/crossfade
    final concatInputs = <String>[];
    for (final img in imagePaths) {
      concatInputs.add('-loop 1 -t ${clipSeconds.toStringAsFixed(3)} -i "${img}"');
    }
    final concatFilter = StringBuffer();
    for (var i = 0; i < imagePaths.length; i++) {
      concatFilter.write('[$i:v]scale=${width}:${height}:force_original_aspect_ratio=cover,setsar=1,format=yuv420p[v$i];');
    }
    final concatLabels = List.generate(imagePaths.length, (i) => '[v$i]').join();
    concatFilter.write('${concatLabels}concat=n=${imagePaths.length}:v=1:a=0[v]');

    final fallbackCmd = StringBuffer()
      ..write(concatInputs.join(' '))
      ..write(' -filter_complex "')
      ..write(concatFilter.toString())
      ..write('" -map "[v]" -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -movflags +faststart -an "${outPath}"');

    final fallbackSession = await FFmpegKit.execute(fallbackCmd.toString());
    final frc = await fallbackSession.getReturnCode();
    if (ReturnCode.isSuccess(frc)) {
      return outPath;
    }

    final logs = await session.getAllLogsAsString();
    final flog = await fallbackSession.getAllLogsAsString();
    throw Exception('FFmpeg failed. primary=${rc?.getValue()} fallback=${frc?.getValue()}\n$logs\n----\n$flog');
  }
}

