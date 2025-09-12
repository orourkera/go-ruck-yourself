import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:rucking_app/core/utils/app_logger.dart';

/// Minimal SSE client for OpenAI Responses API streaming (o3 models, etc.).
class OpenAIResponsesService {
  final String apiKey;
  final String baseUrl;

  OpenAIResponsesService(
      {required this.apiKey, this.baseUrl = 'https://api.openai.com/v1'});

  /// Streams a response from the Responses API.
  /// Calls [onDelta] with incremental text, and [onComplete] with the full text once completed.
  /// Supports both legacy string input and new instructions+input separation.
  Future<void> stream({
    required String model,
    String? input,
    String? instructions,
    List<Map<String, dynamic>>? messages,
    double? temperature,
    int? maxOutputTokens,
    bool? store,
    List<Map<String, dynamic>>? tools,
    Map<String, dynamic>? textFormat,
    void Function(String delta)? onDelta,
    required void Function(String full) onComplete,
    void Function(Object error)? onError,
  }) async {
    final uri = Uri.parse('$baseUrl/responses');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };

    final body = <String, dynamic>{
      'model': model,
      'stream': true,
    };

    // Support both legacy input and new instructions+input separation
    if (instructions != null && input != null) {
      body['instructions'] = instructions;
      body['input'] = input;
    } else if (messages != null) {
      body['input'] = messages;
    } else if (input != null) {
      body['input'] = input;
    } else {
      throw ArgumentError(
          'Must provide either input, or instructions+input, or messages');
    }

    // Optional parameters
    final isO3 = model.toLowerCase().startsWith('o3');
    final isO1 = model.toLowerCase().startsWith('o1');
    final isGPT5 = model.toLowerCase().startsWith('gpt-5');
    // Reasoning models (o3*, o1*) do not accept temperature; GPT-5 and others do
    if (!isO3 && !isO1 && temperature != null)
      body['temperature'] = temperature;
    if (maxOutputTokens != null) body['max_output_tokens'] = maxOutputTokens;
    if (store != null) body['store'] = store;
    if (tools != null && tools.isNotEmpty) body['tools'] = tools;
    if (textFormat != null) {
      body['text'] = {'format': textFormat};
    }

    AppLogger.info('[OPENAI_SSE] Starting stream to $uri with model=$model');
    AppLogger.debug(
        '[OPENAI_SSE] Request body: ${jsonEncode(body).substring(0, jsonEncode(body).length.clamp(0, 500))}...');
    final req = http.Request('POST', uri)
      ..headers.addAll(headers)
      ..body = jsonEncode(body);

    StringBuffer full = StringBuffer();
    try {
      final resp = await http.Client().send(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final text = await resp.stream.bytesToString();
        throw Exception('OpenAI SSE error ${resp.statusCode}: $text');
      }

      // Parse SSE lines
      await resp.stream
          .transform(const Utf8Decoder())
          .transform(const LineSplitter())
          .forEach((line) {
        if (line.isEmpty) return; // SSE chunk separator
        if (!line.startsWith('data:')) return;
        final dataStr = line.substring(5).trim();
        if (dataStr == '[DONE]') {
          // End of stream
          return;
        }
        try {
          final map = jsonDecode(dataStr) as Map<String, dynamic>;
          final type = map['type']?.toString() ?? '';

          AppLogger.debug('[OPENAI_SSE] Processing event: $type');

          // Handle different Responses API events
          if (type == 'response.output_text.delta') {
            final delta = (map['delta'] ?? '').toString();
            if (delta.isNotEmpty) {
              full.write(delta);
              if (onDelta != null) onDelta(delta);
              AppLogger.debug(
                  '[OPENAI_SSE] Got delta: ${delta.substring(0, delta.length.clamp(0, 50))}...');
            }
          } else if (type == 'response.output_item.done') {
            // This is the key event where we should extract the final text
            AppLogger.info('[OPENAI_SSE] Processing output_item.done event...');

            // The key field here is 'item' - extract from item first
            final item = map['item'] as Map<String, dynamic>?;
            if (item != null) {
              final itemType = item['type']?.toString() ?? '';
              AppLogger.debug(
                  '[OPENAI_SSE] Found item object of type: $itemType');

              // Only process message items, skip reasoning items
              if (itemType == 'message') {
                String itemText = _extractTextFromResponsesAPI(item);
                if (itemText.isNotEmpty) {
                  full.clear();
                  full.write(itemText);
                  AppLogger.info(
                      '[OPENAI_SSE] Extracted ${itemText.length} chars from message item');
                } else {
                  AppLogger.debug(
                      '[OPENAI_SSE] Message item keys: ${item.keys.toList()}');
                }
              } else if (itemType == 'reasoning') {
                AppLogger.debug(
                    '[OPENAI_SSE] Skipping reasoning item (type: $itemType)');
              } else {
                AppLogger.debug(
                    '[OPENAI_SSE] Unknown item type: $itemType, keys: ${item.keys.toList()}');
              }
            }

            // Try to extract from the response field as fallback
            final response = map['response'] as Map<String, dynamic>?;
            if (response != null && full.isEmpty) {
              AppLogger.debug(
                  '[OPENAI_SSE] Found response object, extracting text...');
              String finalText = _extractTextFromResponsesAPI(response);
              if (finalText.isNotEmpty) {
                full.clear();
                full.write(finalText);
                AppLogger.info(
                    '[OPENAI_SSE] Extracted ${finalText.length} chars from response object');
              }
            }

            // Also try extracting from the event itself as last resort
            if (full.isEmpty) {
              String eventText = _extractTextFromResponsesAPI(map);
              if (eventText.isNotEmpty) {
                full.clear();
                full.write(eventText);
                AppLogger.info(
                    '[OPENAI_SSE] Extracted ${eventText.length} chars from event object');
              }
            }
          } else if (type == 'response.completed') {
            AppLogger.info('[OPENAI_SSE] Response completed event');
            // If we don't have content yet, try to extract from the completed response
            if (full.isEmpty) {
              final response = map['response'] as Map<String, dynamic>?;
              if (response != null) {
                AppLogger.debug(
                    '[OPENAI_SSE] Trying to extract final text from completed response...');

                // The response has an 'output' field containing the message items
                final output = response['output'] as List<dynamic>?;
                if (output != null) {
                  AppLogger.debug(
                      '[OPENAI_SSE] Found output array with ${output.length} items');

                  // Look for message items in the output array
                  for (int i = 0; i < output.length; i++) {
                    final item = output[i] as Map<String, dynamic>?;
                    if (item != null) {
                      final itemType = item['type']?.toString() ?? '';
                      AppLogger.debug(
                          '[OPENAI_SSE] Output item $i: type=$itemType, keys=${item.keys.toList()}');

                      if (itemType == 'message') {
                        // Extract text from message content based on official response structure
                        final content = item['content'] as List<dynamic>?;
                        if (content != null) {
                          AppLogger.debug(
                              '[OPENAI_SSE] Message content has ${content.length} items');
                          for (int j = 0; j < content.length; j++) {
                            final contentItem = content[j];
                            if (contentItem is Map<String, dynamic>) {
                              final contentType =
                                  contentItem['type']?.toString() ?? '';
                              AppLogger.debug(
                                  '[OPENAI_SSE] Content item $j: type=$contentType');

                              if (contentType == 'output_text') {
                                final text = contentItem['text'];
                                if (text is String && text.isNotEmpty) {
                                  full.clear();
                                  full.write(text);
                                  AppLogger.info(
                                      '[OPENAI_SSE] Extracted ${text.length} chars from output_text content');
                                  break;
                                }
                              }
                            }
                          }
                        }
                        if (full.isNotEmpty) break;
                      }
                    }
                  }
                }

                // If still no text found, try the top-level 'text' field for structured outputs
                if (full.isEmpty) {
                  final textField = response['text'];
                  if (textField is String && textField.isNotEmpty) {
                    full.clear();
                    full.write(textField);
                    AppLogger.info(
                        '[OPENAI_SSE] Extracted ${textField.length} chars from top-level text field');
                  } else if (textField is Map<String, dynamic>) {
                    // The text field might be an object for structured outputs
                    final textContent = textField['content']?.toString();
                    if (textContent != null && textContent.isNotEmpty) {
                      full.clear();
                      full.write(textContent);
                      AppLogger.info(
                          '[OPENAI_SSE] Extracted ${textContent.length} chars from text.content field');
                    } else {
                      AppLogger.debug(
                          '[OPENAI_SSE] Text field keys: ${textField.keys.toList()}');
                    }
                  } else {
                    AppLogger.error(
                        '[OPENAI_SSE] Text field type: ${textField.runtimeType}, value: $textField');
                  }
                }

                if (full.isEmpty) {
                  AppLogger.error(
                      '[OPENAI_SSE] Still no text found after checking all fields');
                }
              } else {
                AppLogger.error(
                    '[OPENAI_SSE] No response object in completed event');
              }
            }
          } else {
            AppLogger.debug('[OPENAI_SSE] Other event: $type');
          }
        } catch (e) {
          AppLogger.warning(
              '[OPENAI_SSE] Failed to parse SSE line: $e. Line: $dataStr');
        }
      });

      final out = full.toString();
      AppLogger.info('[OPENAI_SSE] Completed stream; bytes=${out.length}');
      onComplete(out);
    } catch (e) {
      AppLogger.error('[OPENAI_SSE] Stream error: $e');
      if (onError != null) onError(e);
    }
  }

  /// Extract text content from Responses API structure: output[].content[].text
  String _extractTextFromResponsesAPI(Map<String, dynamic> data) {
    final buffer = StringBuffer();

    // Try multiple possible paths for text extraction

    // Path 1: output[].content[].text (main structure)
    final output = data['output'] as List<dynamic>?;
    if (output != null) {
      for (final item in output) {
        if (item is Map<String, dynamic>) {
          final content = item['content'] as List<dynamic>?;
          if (content != null) {
            for (final contentItem in content) {
              if (contentItem is Map<String, dynamic>) {
                final text = contentItem['text'];
                if (text is String && text.isNotEmpty) {
                  buffer.write(text);
                }
              }
            }
          }
        }
      }
    }

    // Path 2: Try direct text field
    final directText = data['text'];
    if (directText is String && directText.isNotEmpty && buffer.isEmpty) {
      buffer.write(directText);
    }

    // Path 3: Try content.text directly
    final content = data['content'];
    if (content is Map<String, dynamic>) {
      final text = content['text'];
      if (text is String && text.isNotEmpty && buffer.isEmpty) {
        buffer.write(text);
      }
    }

    // Path 4: Try content as list
    if (content is List<dynamic> && buffer.isEmpty) {
      for (final item in content) {
        if (item is Map<String, dynamic>) {
          final text = item['text'];
          if (text is String && text.isNotEmpty) {
            buffer.write(text);
          }
        }
      }
    }

    final result = buffer.toString();
    if (result.isNotEmpty) {
      AppLogger.debug(
          '[OPENAI_SSE] Extracted text: ${result.substring(0, result.length.clamp(0, 100))}...');
    }

    return result;
  }
}
