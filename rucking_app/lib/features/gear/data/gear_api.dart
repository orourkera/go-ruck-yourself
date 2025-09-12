import 'package:dio/dio.dart';

class GearApi {
  final Dio _dio;
  GearApi(this._dio);

  Future<List<dynamic>> searchCurated({required String q, String? category}) async {
    final res = await _dio.get('/api/gear/search', queryParameters: {
      if (q.isNotEmpty) 'q': q,
      if (category != null) 'category': category,
      'limit': 20,
    });
    return (res.data['items'] as List?) ?? [];
  }

  Future<Map<String, dynamic>> profileGear(String userId) async {
    final res = await _dio.get('/api/gear/profile/$userId');
    return res.data as Map<String, dynamic>;
  }

  Future<void> claimCurated({required String gearItemId, required String relation, String visibility = 'public'}) async {
    await _dio.post('/api/gear/claim', data: {
      'gear_item_id': gearItemId,
      'relation': relation,
      'visibility': visibility,
    });
  }

  Future<void> claimExternal({required String source, required String externalId, required String relation, String? title, String? imageUrl, String visibility = 'public'}) async {
    await _dio.post('/api/gear/claim', data: {
      'source': source,
      'external_id': externalId,
      'relation': relation,
      'title': title,
      'image_url': imageUrl,
      'visibility': visibility,
    });
  }

  Future<void> unclaim({String? gearItemId, String? externalProductId, required String relation}) async {
    await _dio.post('/api/gear/unclaim', data: {
      if (gearItemId != null) 'gear_item_id': gearItemId,
      if (externalProductId != null) 'external_product_id': externalProductId,
      'relation': relation,
    });
  }
}

