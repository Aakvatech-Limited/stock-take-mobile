import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_count/utilis/auth_session.dart';

const baseUrl = 'https://erp.test';
const tokenPath = '/api/method/frappe.integrations.oauth2.get_token';
const syncPath = '/api/method/nex_bridge.api.stock_take.sync_entry';

void main() {
  late List<http.Request> requests;

  void givenSession({required Duration expiresIn, String refresh = 'r1'}) {
    SharedPreferences.setMockInitialValues({
      'base_url': baseUrl,
      'client_id': 'client',
      'accessToken': 'old',
      'refreshToken': refresh,
      'tokenExpiry': DateTime.now().add(expiresIn).toString(),
    });
  }

  // Runs [body] with a fake server. [handler] answers each request.
  Future<T> withServer<T>(
    Future<T> Function() body,
    Future<http.Response> Function(http.Request) handler,
  ) {
    requests = [];
    return http.runWithClient(body, () {
      return MockClient((request) {
        requests.add(request);
        return handler(request);
      });
    });
  }

  http.Response tokenResponse(String access, {String? refresh}) {
    return http.Response(
      jsonEncode({
        'access_token': access,
        if (refresh != null) 'refresh_token': refresh,
        'expires_in': 3600,
      }),
      200,
    );
  }

  test('returns a fresh token without calling the server', () async {
    givenSession(expiresIn: const Duration(hours: 1));
    final token = await withServer(
      AuthSession.getValidAccessToken,
      (_) async => fail('no request expected'),
    );
    expect(token, 'old');
    expect(requests, isEmpty);
  });

  test('refreshes an expired token and saves the new tokens', () async {
    givenSession(expiresIn: const Duration(minutes: -5));
    final token = await withServer(
      AuthSession.getValidAccessToken,
      (_) async => tokenResponse('new', refresh: 'r2'),
    );

    expect(token, 'new');
    expect(requests.single.url.path, tokenPath);
    expect(requests.single.bodyFields, {
      'grant_type': 'refresh_token',
      'refresh_token': 'r1',
      'client_id': 'client',
    });
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('accessToken'), 'new');
    expect(prefs.getString('refreshToken'), 'r2');
    final expiry = DateTime.parse(prefs.getString('tokenExpiry')!);
    expect(expiry.isAfter(DateTime.now().add(const Duration(minutes: 59))),
        isTrue);
  });

  test('refreshes a token that is about to expire', () async {
    givenSession(expiresIn: const Duration(minutes: 1));
    final token = await withServer(
      AuthSession.getValidAccessToken,
      (_) async => tokenResponse('new'),
    );
    expect(token, 'new');
  });

  test('keeps the old refresh token when the server sends none', () async {
    givenSession(expiresIn: Duration.zero);
    await withServer(
      AuthSession.getValidAccessToken,
      (_) async => tokenResponse('new'),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('refreshToken'), 'r1');
  });

  test('overlapping calls share one refresh request', () async {
    givenSession(expiresIn: Duration.zero);
    final tokens = await withServer(
      () => Future.wait(List.generate(3, (_) {
        return AuthSession.getValidAccessToken();
      })),
      (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return tokenResponse('new', refresh: 'r2');
      },
    );
    expect(tokens, ['new', 'new', 'new']);
    expect(requests, hasLength(1));
  });

  test('rejected refresh token means the session expired', () async {
    for (final status in [400, 401, 403, 404]) {
      givenSession(expiresIn: Duration.zero);
      final call = withServer(
        AuthSession.getValidAccessToken,
        (_) async => http.Response('{"error":"invalid_grant"}', status),
      );
      await expectLater(
        call,
        throwsA(isA<SessionException>()
            .having((e) => e.sessionExpired, 'sessionExpired', isTrue)),
        reason: 'status $status',
      );
    }
  });

  test('missing refresh token means the session expired', () async {
    givenSession(expiresIn: Duration.zero, refresh: '');
    await expectLater(
      withServer(AuthSession.getValidAccessToken,
          (_) async => fail('no request expected')),
      throwsA(isA<SessionException>()
          .having((e) => e.sessionExpired, 'sessionExpired', isTrue)),
    );
  });

  test('no network during refresh means offline, tokens untouched', () async {
    givenSession(expiresIn: Duration.zero);
    await expectLater(
      withServer(AuthSession.getValidAccessToken,
          (_) async => throw const SocketException('no route')),
      throwsA(isA<SessionException>()
          .having((e) => e.sessionExpired, 'sessionExpired', isFalse)),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('accessToken'), 'old');
    expect(prefs.getString('refreshToken'), 'r1');
  });

  test('server error during refresh is not reported as expired', () async {
    givenSession(expiresIn: Duration.zero);
    await expectLater(
      withServer(AuthSession.getValidAccessToken,
          (_) async => http.Response('boom', 502)),
      throwsA(isNot(isA<SessionException>())),
    );
  });

  test('a failed refresh does not block the next attempt', () async {
    givenSession(expiresIn: Duration.zero);
    await expectLater(
      withServer(AuthSession.getValidAccessToken,
          (_) async => throw const SocketException('no route')),
      throwsA(isA<SessionException>()),
    );
    final token = await withServer(
      AuthSession.getValidAccessToken,
      (_) async => tokenResponse('new'),
    );
    expect(token, 'new');
  });

  group('post', () {
    test('sends the bearer token and JSON body', () async {
      givenSession(expiresIn: const Duration(hours: 1));
      final response = await withServer(
        () => AuthSession.post('nex_bridge.api.stock_take.sync_entry',
            body: {'api_call_type': 'get_entries'}),
        (_) async => http.Response('{}', 200),
      );
      expect(response.statusCode, 200);
      final request = requests.single;
      expect(request.url.toString(), '$baseUrl$syncPath');
      expect(request.headers['Authorization'], 'Bearer old');
      expect(jsonDecode(request.body), {'api_call_type': 'get_entries'});
    });

    test('refreshes before posting when the token expired', () async {
      givenSession(expiresIn: Duration.zero);
      await withServer(
        () => AuthSession.post('nex_bridge.api.stock_take.sync_entry'),
        (request) async => request.url.path == tokenPath
            ? tokenResponse('new')
            : http.Response('{}', 200),
      );
      expect(requests.map((r) => r.url.path), [tokenPath, syncPath]);
      expect(requests.last.headers['Authorization'], 'Bearer new');
    });

    test('on 401 refreshes once and retries with the new token', () async {
      givenSession(expiresIn: const Duration(hours: 1));
      final response = await withServer(
        () => AuthSession.post('nex_bridge.api.stock_take.sync_entry'),
        (request) async {
          if (request.url.path == tokenPath) return tokenResponse('new');
          final auth = request.headers['Authorization'];
          return http.Response('{}', auth == 'Bearer new' ? 200 : 401);
        },
      );
      expect(response.statusCode, 200);
      expect(requests.map((r) => r.url.path), [syncPath, tokenPath, syncPath]);
    });

    test('does not loop when the retry is also rejected', () async {
      givenSession(expiresIn: const Duration(hours: 1));
      final response = await withServer(
        () => AuthSession.post('nex_bridge.api.stock_take.sync_entry'),
        (request) async => request.url.path == tokenPath
            ? tokenResponse('new')
            : http.Response('{}', 403),
      );
      expect(response.statusCode, 403);
      expect(requests, hasLength(3));
    });

    test('no network while posting means offline', () async {
      givenSession(expiresIn: const Duration(hours: 1));
      await expectLater(
        withServer(
            () => AuthSession.post('nex_bridge.api.stock_take.sync_entry'),
            (_) async => throw const SocketException('no route')),
        throwsA(isA<SessionException>()
            .having((e) => e.sessionExpired, 'sessionExpired', isFalse)),
      );
    });
  });
}
