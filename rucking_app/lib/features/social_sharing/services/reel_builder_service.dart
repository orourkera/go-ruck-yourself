import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/return_code.dart';
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
        ..write('scale=${width}:${height}:force_original_aspect_ratio=increase,')
        ..write('crop=${width}:${height},setsar=1,')
        ..write("zoompan=z='if(eq(on,0),${zoomStart.toStringAsFixed(3)},min(max(pzoom,${zoomStart.toStringAsFixed(3)})+${zoomRate.toStringAsFixed(5)},${zoomEnd.toStringAsFixed(3)}))':d=${frames}:s=${width}x${height}:fps=${fps},")
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
      concatFilter.write('[$i:v]scale=${width}:${height}:force_original_aspect_ratio=increase,crop=${width}:${height},setsar=1,format=yuv420p[v$i];');
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

    // Final fallback: generate per-image MP4 clips then concat (no complex filters)
    final segments = <String>[];
    for (var i = 0; i < imagePaths.length; i++) {
      final segPath = p.join(reelsDir.path, 'seg_${DateTime.now().millisecondsSinceEpoch}_$i.mp4');
      final img = imagePaths[i];
      final segCmd = StringBuffer()
        ..write('-loop 1 -t ${clipSeconds.toStringAsFixed(3)} -r $fps -i ')
        ..write(_quote(img))
        ..write(' -vf ')
        ..write(_quote('scale=${width}:${height}:force_original_aspect_ratio=increase,crop=${width}:${height},setsar=1,format=yuv420p'))
        ..write(' -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -movflags +faststart -an ')
        ..write(_quote(segPath));

      final segSession = await FFmpegKit.execute(segCmd.toString());
      if (!ReturnCode.isSuccess(await segSession.getReturnCode())) {
        final logs = await segSession.getAllLogsAsString();
        throw Exception('FFmpeg segment encode failed for $img\n$logs');
      }
      segments.add(segPath);
    }

    // Write concat list
    final listPath = p.join(reelsDir.path, 'concat_${DateTime.now().millisecondsSinceEpoch}.txt');
    final listFile = File(listPath);
    final listContent = segments.map((s) => "file ${_quoteForConcat(s)}").join("\n");
    await listFile.writeAsString(listContent);

    final concatCmd = StringBuffer()
      ..write('-f concat -safe 0 -i ')
      ..write(_quote(listPath))
      ..write(' -c copy -movflags +faststart ')
      ..write(_quote(outPath));

    final concatSession = await FFmpegKit.execute(concatCmd.toString());
    final crc = await concatSession.getReturnCode();
    if (ReturnCode.isSuccess(crc)) {
      return outPath;
    }

    final logs = await session.getAllLogsAsString();
    final flog = await fallbackSession.getAllLogsAsString();
    final clog = await concatSession.getAllLogsAsString();
    throw Exception('FFmpeg failed. primary=${rc?.getValue()} fallback=${frc?.getValue()} concat=${crc?.getValue()}\n$logs\n----\n$flog\n----\n$clog');
  }

  String _quote(String path) {
    if (path.contains(' ')) {
      return '\'' + path.replaceAll("'", "'\\''") + '\'';
    }
    return path;
  }

  String _quoteForConcat(String path) {
    // Concat list requires quoted paths if spaces exist
    return '\'' + path.replaceAll("'", "'\\''") + '\'';
  }
}
