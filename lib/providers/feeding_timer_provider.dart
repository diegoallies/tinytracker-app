import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FeedingTimerState {
  final int elapsedSeconds;
  final bool isRunning;
  final String selectedType;

  const FeedingTimerState({
    this.elapsedSeconds = 0,
    this.isRunning = false,
    this.selectedType = 'breast_left',
  });

  FeedingTimerState copyWith({
    int? elapsedSeconds,
    bool? isRunning,
    String? selectedType,
  }) {
    return FeedingTimerState(
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      isRunning: isRunning ?? this.isRunning,
      selectedType: selectedType ?? this.selectedType,
    );
  }
}

class FeedingTimerNotifier extends StateNotifier<FeedingTimerState> {
  Timer? _timer;

  FeedingTimerNotifier() : super(const FeedingTimerState());

  void startTimer() {
    _timer?.cancel();
    state = state.copyWith(isRunning: true, elapsedSeconds: 0);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
    });
  }

  void stopTimer() {
    _timer?.cancel();
    state = state.copyWith(isRunning: false);
  }

  void resetTimer() {
    _timer?.cancel();
    state = state.copyWith(elapsedSeconds: 0, isRunning: false);
  }

  void selectType(String type) {
    if (state.isRunning) stopTimer();
    state = state.copyWith(selectedType: type);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final feedingTimerProvider =
    StateNotifierProvider<FeedingTimerNotifier, FeedingTimerState>((ref) {
  return FeedingTimerNotifier();
});
