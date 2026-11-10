import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/body_profile.dart';
import '../models/gemini_fashion.dart';
import '../models/outfit_flow_context.dart';
import '../screens/outfit_analysis_screen.dart';
import '../screens/outfit_chat_screen.dart';
import '../screens/outfit_suggestion_screen.dart';
import '../screens/personal_info_screen.dart';
import '../services/body_profile_store.dart';
import '../services/gemini_fashion_service.dart';
import '../services/chat_history_store.dart';
import '../services/analysis_preferences.dart';

/// Giữ bối cảnh bộ đồ trong phiên hiện tại, không lưu ảnh hay gọi AI khi đổi tab.
class AppHome extends StatefulWidget {
  const AppHome({
    super.key,
    required this.profileStore,
    required this.accountName,
    required this.accountEmail,
    required this.onChangePassword,
    required this.onSignOut,
    this.chatService,
    this.chatHistoryStore,
    this.preferencesStore,
  });

  final BodyProfileStore profileStore;
  final String accountName;
  final String accountEmail;
  final Future<void> Function(String, String) onChangePassword;
  final Future<void> Function() onSignOut;
  final GeminiFashionServiceContract? chatService;
  final ChatHistoryStore? chatHistoryStore;
  final AnalysisPreferencesStore? preferencesStore;

  @override
  State<AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends State<AppHome> {
  late final SessionBodyProfileStore _profiles;
  String? _profileFingerprint;
  int _tab = 0;
  int _suggestionRevision = 0;
  int _profileRevision = 0;
  bool _suggestionOpened = false;
  bool _suggestionDirty = false;
  bool _chatOpened = false;
  bool _profileOpened = false;
  OutfitFlowContext _flow = const OutfitFlowContext();
  GeminiOutfitContext _chatContext = const OutfitFlowContext().chatContext;

  @override
  void initState() {
    super.initState();
    _profiles = SessionBodyProfileStore(widget.profileStore);
    _profiles.addListener(_profileSaved);
  }

  void _profileSaved() => _profilesChanged(_profiles.value!);

  @override
  void dispose() {
    _profiles.removeListener(_profileSaved);
    _profiles.dispose();
    super.dispose();
  }

  void _analysisChanged(OutfitFlowContext flow) {
    setState(() {
      _flow = flow;
      if (_tab == 0 || !_suggestionOpened) {
        _chatContext = flow.chatContext;
      }
      // Offstage profile reloads must not erase the choices in Gợi ý.
      if (_tab == 0) _suggestionDirty = true;
    });
  }

  void _openSuggestion(OutfitFlowContext flow) {
    setState(() {
      _flow = flow;
      _chatContext = flow.chatContext;
      _suggestionRevision++;
      _suggestionOpened = true;
      _suggestionDirty = false;
      _tab = 1;
    });
  }

  void _adviceReady(GeminiOutfitContext context, GeminiSuggestion _) {
    setState(() {
      _chatContext = context;
    });
  }

  void _profilesChanged(BodyProfileCollection collection) {
    final fingerprint = jsonEncode(collection.toJson());
    if (fingerprint == _profileFingerprint) return;
    _profileFingerprint = fingerprint;
    _profiles.acceptSavedCollection(collection);
    final profile = collection.selected;
    setState(() {
      _profileRevision++;
      _flow = OutfitFlowContext(
        season: _flow.season,
        temperature: _flow.temperature,
        style: _flow.style,
        occasion: _flow.occasion,
        useCurrentWeather: _flow.useCurrentWeather,
        weather: _flow.weather,
        heightCm: profile?.heightCm,
        weightKg: profile?.weightKg,
        gender: profile?.gender ?? BodyGender.unspecified,
      );
      _chatContext = GeminiOutfitContext(
        items: const [],
        weather: _chatContext.weather,
        season: _chatContext.season,
        style: _chatContext.style,
        occasion: _chatContext.occasion,
        temperatureC: _chatContext.temperatureC,
        heightCm: profile?.heightCm,
        weightKg: profile?.weightKg,
        gender: profile?.gender ?? BodyGender.unspecified,
      );
    });
  }

  void _selectTab(int index) {
    setState(() {
      if (index == 1) {
        _suggestionOpened = true;
        if (_suggestionDirty) {
          _suggestionRevision++;
          _suggestionDirty = false;
        }
      }
      if (index == 2) _chatOpened = true;
      if (index == 3) _profileOpened = true;
      _tab = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final flow = _flow;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: <Widget>[
          OutfitAnalysisScreen(
            profileStore: _profiles,
            preferencesStore: widget.preferencesStore,
            accountName: widget.accountName,
            accountEmail: widget.accountEmail,
            onChangePassword: widget.onChangePassword,
            onSignOut: widget.onSignOut,
            onAnalysisCompleted: _analysisChanged,
            onSuggestionRequested: _openSuggestion,
            onPersonalRequested: () => _selectTab(3),
            profileRevision: _profileRevision,
          ),
          if (_suggestionOpened)
            OutfitSuggestionScreen(
              key: ValueKey<int>(_suggestionRevision),
              profileStore: _profiles,
              initialSeason: flow.season,
              initialTemperatureC: flow.temperature,
              initialStyle: flow.style,
              initialOccasion: flow.occasion,
              initialMode: flow.useCurrentWeather
                  ? SuggestionMode.currentWeather
                  : SuggestionMode.manual,
              initialWeather: flow.weather,
              initialHeightCm: flow.heightCm,
              initialWeightKg: flow.weightKg,
              initialGender: flow.gender,
              onAdviceReady: _adviceReady,
              onContextChanged: (contextData) {
                setState(() => _chatContext = contextData);
              },
              onOpenChat: () => _selectTab(2),
              profileRevision: _profileRevision,
            )
          else
            const SizedBox.shrink(),
          if (_chatOpened)
            OutfitChatScreen(
              // Đổi bối cảnh chỉ cập nhật dữ liệu cho câu hỏi tiếp theo.
              // Giữ State để không mất lịch sử, bản nháp và request đang chờ.
              key: const ValueKey<String>('outfit_chat'),
              contextData: _chatContext,
              service: widget.chatService,
              historyStore: widget.chatHistoryStore,
            )
          else
            const SizedBox.shrink(),
          if (_profileOpened)
            PersonalInfoScreen(
              accountName: widget.accountName,
              email: widget.accountEmail,
              profileStore: _profiles,
              profileRevision: _profileRevision,
              onChangePassword: widget.onChangePassword,
              onProfilesChanged: _profilesChanged,
              onSignOut: widget.onSignOut,
            )
          else
            const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: _selectTab,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon: Icon(Icons.document_scanner),
            label: 'Phân tích',
          ),
          NavigationDestination(
            icon: Icon(Icons.checkroom_outlined),
            selectedIcon: Icon(Icons.checkroom),
            label: 'Gợi ý',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Hỏi đáp',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Cá nhân',
          ),
        ],
      ),
    );
  }
}
