import 'package:dio/dio.dart';
import 'package:rucking_app/core/services/api_client.dart';

class GearApi {
  final Dio _dio;
  GearApi(this._dio);
  GearApi.fromClient(ApiClient client) : _dio = _ApiClientAdapter(client);

  Future<List<dynamic>> searchCurated(
      {required String q, String? category}) async {
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

  Future<void> claimCurated(
      {required String gearItemId,
      required String relation,
      String visibility = 'public'}) async {
    await _dio.post('/api/gear/claim', data: {
      'gear_item_id': gearItemId,
      'relation': relation,
      'visibility': visibility,
    });
  }

  Future<void> claimExternal(
      {required String source,
      required String externalId,
      required String relation,
      String? title,
      String? imageUrl,
      String visibility = 'public'}) async {
    await _dio.post('/api/gear/claim', data: {
      'source': source,
      'external_id': externalId,
      'relation': relation,
      'title': title,
      'image_url': imageUrl,
      'visibility': visibility,
    });
  }

  Future<void> unclaim(
      {String? gearItemId,
      String? externalProductId,
      required String relation}) async {
    await _dio.post('/api/gear/unclaim', data: {
      if (gearItemId != null) 'gear_item_id': gearItemId,
      if (externalProductId != null) 'external_product_id': externalProductId,
      'relation': relation,
    });
  }

  Future<List<dynamic>> getCuratedComments(String itemId) async {
    final res = await _dio.get('/api/gear/items/$itemId/comments');
    return (res.data['items'] as List?) ?? [];
  }

  Future<void> postCuratedComment({
    required String itemId,
    int? rating,
    String? title,
    required String body,
    bool ownershipClaimed = false,
  }) async {
    await _dio.post('/api/gear/items/$itemId/comments', data: {
      if (rating != null) 'rating': rating,
      if (title != null && title.isNotEmpty) 'title': title,
      'body': body,
      'ownership_claimed': ownershipClaimed,
    });
  }

  Future<Map<String, dynamic>> getItemDetail(String itemId) async {
    final res = await _dio.get('/api/gear/items/$itemId');
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<List<dynamic>> searchAmazon(
      {required String q, String? category, int page = 1}) async {
    final res = await _dio.get('/api/amazon/search', queryParameters: {
      if (q.isNotEmpty) 'q': q,
      if (category != null) 'category': category,
      if (page != 1) 'page': page,
    });
    return (res.data['items'] as List?) ?? [];
  }
}

class _ApiClientAdapter implements Dio {
  final ApiClient _client;
  _ApiClientAdapter(this._client);

  // Implement only the used subset via delegation to ApiClient
  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? queryParameters,
      Options? options,
      CancelToken? cancelToken,
      ProgressCallback? onReceiveProgress}) async {
    final data = await _client.get(path, queryParams: queryParameters);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: data as T?,
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> post<T>(String path,
      {data,
      Map<String, dynamic>? queryParameters,
      Options? options,
      CancelToken? cancelToken,
      ProgressCallback? onSendProgress,
      ProgressCallback? onReceiveProgress}) async {
    final res = await _client.post(path, data: data);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: res as T?,
      statusCode: 200,
    );
  }

  // The rest of Dio interface is not used by GearApi; throw for clarity if called
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
