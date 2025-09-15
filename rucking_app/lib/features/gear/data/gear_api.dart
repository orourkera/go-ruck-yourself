import 'package:dio/dio.dart';
import 'package:rucking_app/core/services/api_client.dart';

class GearApi {
  final Dio? _dio;
  final ApiClient? _client;

  GearApi(Dio dio)
      : _dio = dio,
        _client = null;
  GearApi.fromClient(ApiClient client)
      : _dio = null,
        _client = client;

  Future<List<dynamic>> searchCurated(
      {required String q, String? category}) async {
    if (_client != null) {
      final res = await _client!.get('/api/gear/search', queryParams: {
        if (q.isNotEmpty) 'q': q,
        if (category != null) 'category': category,
        'limit': 20,
      });
      return (res['items'] as List?) ?? [];
    } else {
      final res = await _dio!.get('/api/gear/search', queryParameters: {
        if (q.isNotEmpty) 'q': q,
        if (category != null) 'category': category,
        'limit': 20,
      });
      return (res.data['items'] as List?) ?? [];
    }
  }

  Future<Map<String, dynamic>> profileGear(String userId) async {
    if (_client != null) {
      final res = await _client!.get('/api/gear/profile/$userId');
      return res as Map<String, dynamic>;
    } else {
      final res = await _dio!.get('/api/gear/profile/$userId');
      return res.data as Map<String, dynamic>;
    }
  }

  Future<void> claimCurated(
      {required String gearItemId,
      required String relation,
      String visibility = 'public'}) async {
    final payload = {
      'gear_item_id': gearItemId,
      'relation': relation,
      'visibility': visibility,
    };
    if (_client != null) {
      await _client!.post('/api/gear/claim', payload);
    } else {
      await _dio!.post('/api/gear/claim', data: payload);
    }
  }

  Future<void> claimExternal(
      {required String source,
      required String externalId,
      required String relation,
      String? title,
      String? imageUrl,
      String visibility = 'public'}) async {
    final payload = {
      'source': source,
      'external_id': externalId,
      'relation': relation,
      'title': title,
      'image_url': imageUrl,
      'visibility': visibility,
    };
    if (_client != null) {
      await _client!.post('/api/gear/claim', payload);
    } else {
      await _dio!.post('/api/gear/claim', data: payload);
    }
  }

  Future<void> unclaim(
      {String? gearItemId,
      String? externalProductId,
      required String relation}) async {
    final payload = {
      if (gearItemId != null) 'gear_item_id': gearItemId,
      if (externalProductId != null) 'external_product_id': externalProductId,
      'relation': relation,
    };
    if (_client != null) {
      await _client!.post('/api/gear/unclaim', payload);
    } else {
      await _dio!.post('/api/gear/unclaim', data: payload);
    }
  }

  Future<List<dynamic>> getCuratedComments(String itemId) async {
    if (_client != null) {
      final res = await _client!.get('/api/gear/items/$itemId/comments');
      return (res['items'] as List?) ?? [];
    } else {
      final res = await _dio!.get('/api/gear/items/$itemId/comments');
      return (res.data['items'] as List?) ?? [];
    }
  }

  Future<void> postCuratedComment({
    required String itemId,
    int? rating,
    String? title,
    required String body,
    bool ownershipClaimed = false,
  }) async {
    final payload = {
      if (rating != null) 'rating': rating,
      if (title != null && title.isNotEmpty) 'title': title,
      'body': body,
      'ownership_claimed': ownershipClaimed,
    };
    if (_client != null) {
      await _client!.post('/api/gear/items/$itemId/comments', payload);
    } else {
      await _dio!.post('/api/gear/items/$itemId/comments', data: payload);
    }
  }

  Future<Map<String, dynamic>> getItemDetail(String itemId) async {
    if (_client != null) {
      final res = await _client!.get('/api/gear/items/$itemId');
      return (res as Map).cast<String, dynamic>();
    } else {
      final res = await _dio!.get('/api/gear/items/$itemId');
      return (res.data as Map).cast<String, dynamic>();
    }
  }

  Future<List<dynamic>> searchAmazon(
      {required String q, String? category, int page = 1}) async {
    if (_client != null) {
      final res = await _client!.get('/api/amazon/search', queryParams: {
        if (q.isNotEmpty) 'q': q,
        if (category != null) 'category': category,
        if (page != 1) 'page': page,
      });
      return (res['items'] as List?) ?? [];
    } else {
      final res = await _dio!.get('/api/amazon/search', queryParameters: {
        if (q.isNotEmpty) 'q': q,
        if (category != null) 'category': category,
        if (page != 1) 'page': page,
      });
      return (res.data['items'] as List?) ?? [];
    }
  }
}
