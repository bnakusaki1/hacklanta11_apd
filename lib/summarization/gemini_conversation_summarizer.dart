import 'package:flutter_gemini/flutter_gemini.dart';

const geminiApiKey = "AQ.Ab8RN6L20Xq0-Q5s3X739rZII6chF4ekU6pJHxalA6iZph-aTw"; // String.fromEnvironment('GEMINI_API_KEY');

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

    final result = await Gemini.instance.prompt(
      parts: [Part.text(prompt)],
      model: _model,
      generationConfig: GenerationConfig(
        temperature: 0.2,
        maxOutputTokens: maxOutputTokens,
      ),
    );

    final summary = result?.output?.trim();
    if (summary == null || summary.isEmpty) {
      throw StateError('Gemini returned an empty summary. Please try again.');
    }
    return summary;
  }
}
