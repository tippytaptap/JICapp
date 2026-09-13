import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'config.dart';
import 'models.dart';

class RadioController extends ChangeNotifier {
  final Organisation organisation;
  final AudioPlayer player;
  RadioController(this.organisation, {AudioPlayer? player})
    : player = player ?? AudioPlayer() {
    _subscription = this.player.playerStateStream.listen(
      (_) => notifyListeners(),
    );
  }
  StreamSubscription<PlayerState>? _subscription;
  Timer? _sleep;
  DateTime? stopAt;
  bool busy = false;
  int _request = 0;
  bool _disposed = false;
  String? error;
  String? sourceUrl;
  String currentTitle = 'Live radio';
  bool get isRadio => sourceUrl == null || sourceUrl == organisation.radio;
  bool get playing =>
      player.playing && player.processingState != ProcessingState.completed;

  Future<void> play() => _playSource(organisation.radio, 'Live radio');

  Future<void> playRecording(String url, String title) async {
    if (!safeWebUrl(url)) {
      throw ArgumentError('A secure recording URL is required.');
    }
    if (busy) {
      throw StateError('Audio is already opening.');
    }
    await _playSource(url, title);
    if (error != null) throw StateError(error!);
  }

  Future<void> _playSource(String url, String title) async {
    if (busy) return;
    final request = ++_request;
    busy = true;
    error = null;
    notifyListeners();
    try {
      _sleep?.cancel();
      stopAt = null;
      await player.stop();
      if (_disposed || request != _request) return;
      if (!kIsWeb) {
        await (await AudioSession.instance).configure(
          const AudioSessionConfiguration.speech(),
        );
      }
      await player
          .setAudioSource(
            AudioSource.uri(
              Uri.parse(url),
              tag: MediaItem(id: url, title: title, album: organisation.name),
            ),
          )
          .timeout(const Duration(seconds: 25));
      if (_disposed || request != _request) return;
      sourceUrl = url;
      currentTitle = title;
      unawaited(
        player.play().catchError((Object _) {
          if (_disposed || request != _request) return;
          error = 'Audio could not play. Try again.';
          notifyListeners();
        }),
      );
    } catch (_) {
      if (_disposed || request != _request) return;
      error = 'Audio is unavailable. Try again shortly.';
      await player.stop();
    } finally {
      if (!_disposed && request == _request) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> stop() async {
    _request++;
    busy = false;
    _sleep?.cancel();
    stopAt = null;
    await player.stop();
    if (!_disposed) notifyListeners();
  }

  void sleepAfter(int minutes) {
    _sleep?.cancel();
    stopAt = minutes > 0
        ? DateTime.now().add(Duration(minutes: minutes))
        : null;
    if (minutes > 0) _sleep = Timer(Duration(minutes: minutes), stop);
    notifyListeners();
  }

  void resume() {
    if (stopAt?.isBefore(DateTime.now()) ?? false) unawaited(stop());
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _sleep?.cancel();
    _subscription?.cancel();
    player.dispose();
    super.dispose();
  }
}
