import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionException, FunctionResponse;

import '../../core/supabase.dart';
import 'extracted_receipt.dart';

/// Thrown when the user has used up their daily receipt-extraction quota
/// (the Edge Function answers 429 `{code: 'rate_limited'}`). Carries the
/// server-reported [limit] so the UI can show "N per day".
class ExtractionLimitReached implements Exception {
  const ExtractionLimitReached(this.limit);
  final int limit;

  @override
  String toString() => 'ExtractionLimitReached(limit: $limit)';
}

/// Sends a receipt / invoice photo to the `extract-receipt` Edge Function, which
/// runs it through Gemini server-side (keeping the API key off the client) and
/// returns the structured fields. Mirrors [MerchantLookupService]'s shape: the
/// Supabase singleton is touched lazily (not in the constructor) so test fakes
/// that override [extract] never reach the network.
///
/// Unlike the merchant lookup this is **not** best-effort — a failure throws so
/// the scan queue marks that job failed (there's nothing to save without the
/// extraction).
class ReceiptExtractionService {
  ReceiptExtractionService();

  /// Reads [bytes] (a JPEG/PNG receipt photo) into an [ExtractedReceipt].
  Future<ExtractedReceipt> extract(
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
  }) async {
    final FunctionResponse res;
    try {
      res = await supabase.functions.invoke(
        'extract-receipt',
        body: {'image': base64Encode(bytes), 'mimeType': mimeType},
      );
    } on FunctionException catch (e) {
      // functions_client throws on any non-2xx; turn the daily-cap 429 into a
      // typed exception the queue can show as a friendly message.
      if (e.status == 429) {
        final details = e.details;
        final limit = details is Map && details['limit'] is int
            ? details['limit'] as int
            : 30;
        throw ExtractionLimitReached(limit);
      }
      rethrow;
    }
    final data = res.data;
    if (data is! Map) {
      throw StateError('extract-receipt returned an unexpected response');
    }
    if (data['error'] != null) {
      throw StateError('extract-receipt failed: ${data['error']}');
    }
    return ExtractedReceipt.fromJson(Map<String, dynamic>.from(data));
  }
}
