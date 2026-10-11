import 'package:flutter_gemini/flutter_gemini.dart';

const geminiApiKey = "AQ.Ab8RN6K57CBIUHiLxIxsQhGyOTMR_vLN2rvfeh61lrh98Rm6Qw";

class GeminiConversationSummarizer {
  static const _model = 'models/gemini-3.8-flash';

  bool get isConfigured => geminiApiKey.isNotEmpty;

  Future<String> summarizeHighlight(String transcriptContext) {
    return _generate('''
You are a careful conversation note-taker. Summarize the latest meaningful exchange in the transcript below in 1-2 concise sentences. If the latest exchange is a question, accurately restate the question and include only relevant context. Do not invent details, assign speaker names, or answer the question unless the transcript contains the answer. Return only the summary.

Transcript context:
$transcriptContext
''', maxOutputTokens: 180);
  }

  Future<String> summarizeConversation(String transcript) {
    return _generate('''
You are a careful conversation note-taker. Summarize the conversation below in concise bullet points. Capture the main topics, important questions and answers, decisions, and action items. Do not invent details or assign speaker names. If the transcript does not support a detail, leave it out. Return only the summary.

Conversation transcript:
$transcript
''', maxOutputTokens: 700);
  }

  Future<String> _generate(
    String prompt, {
    required int maxOutputTokens,
  }) async {
    if (!isConfigured) {
      throw StateError(
        'Gemini is not configured. Run the app with --dart-define=GEMINI_API_KEY=YOUR_KEY.',
      );
    }

    Candidates? result;
    const maxAttempts = 3;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        result = await Gemini.instance.prompt(
          parts: [Part.text(prompt)],
          model: _model,
          generationConfig: GenerationConfig(
            temperature: 0.2,
            maxOutputTokens: maxOutputTokens,
          ),
        );
        break;
      } on GeminiException catch (error) {
        final isTransient =
            error.statusCode == -1 ||
            const {429, 500, 502, 503, 504}.contains(error.statusCode);

        if (!isTransient || attempt == maxAttempts) {
          if (isTransient) {
            throw StateError(
              'Gemini is temporarily unavailable or your device cannot reach it. Check your connection and try again.',
            );
          }
          rethrow;
        }

        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }

    final summary = result?.output?.trim();
    if (summary == null || summary.isEmpty) {
      throw StateError('Gemini returned an empty summary. Please try again.');
    }
    return summary;
  }
}
