import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/models/child.dart';
import '../core/models/post.dart';
import '../core/models/project.dart';
import '../services/tinhakids_api_service.dart';

class AppState {
  final String? token;
  final List<Child> children;
  final Child? selectedChild;
  final List<Post> posts;
  final List<Project> projects;
  final bool loading;
  final String? error;

  const AppState({
    this.token,
    this.children = const [],
    this.selectedChild,
    this.posts = const [],
    this.projects = const [],
    this.loading = false,
    this.error,
  });

  AppState copyWith({
    String? token,
    List<Child>? children,
    Child? selectedChild,
    List<Post>? posts,
    List<Project>? projects,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return AppState(
      token: token ?? this.token,
      children: children ?? this.children,
      selectedChild: selectedChild ?? this.selectedChild,
      posts: posts ?? this.posts,
      projects: projects ?? this.projects,
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class AppNotifier extends StateNotifier<AppState> {
  AppNotifier(this._api) : super(const AppState());
  final TinhaKidsApiService _api;
  int _requestVersion = 0;

  bool _isCurrent(int version) => mounted && version == _requestVersion;

  Future<bool> restoreSession() async {
    final version = ++_requestVersion;
    state = const AppState(loading: true);
    final token = await _api.getSavedToken();
    if (!_isCurrent(version)) return false;
    if (token == null || token.isEmpty) {
      state = const AppState();
      return false;
    }
    try {
      final children = await _api.getChildren(token);
      if (!_isCurrent(version)) return false;

      final savedChildId = await _api.getSavedChildId();
      if (!_isCurrent(version)) return false;
      final selected =
          children.where((child) => child.id == savedChildId).firstOrNull ??
          children.firstOrNull;
      state = AppState(
        token: token,
        children: children,
        selectedChild: selected,
        loading: selected != null,
        error: selected == null
            ? 'Nenhum aluno está vinculado a esta conta. Consulte a escola.'
            : null,
      );
      await _loadSelected(version);
      return _isCurrent(version);
    } catch (error) {
      if (!_isCurrent(version)) return false;
      state = AppState(
        token: token,
        error:
            'Não foi possível carregar seus alunos. Confira a conexão e atualize.',
      );
      return false;
    }
  }

  Future<void> login(String identifier, String password) async {
    final version = ++_requestVersion;
    state = const AppState(loading: true);
    try {
      final token = await _api.login(identifier, password);
      if (!_isCurrent(version)) return;
      final children = await _api.getChildren(token);
      if (!_isCurrent(version)) return;

      state = AppState(
        token: token,
        children: children,
        selectedChild: children.firstOrNull,
        loading: children.isNotEmpty,
        error: children.isEmpty
            ? 'Nenhum aluno está vinculado a esta conta. Consulte a escola.'
            : null,
      );
      if (children.isNotEmpty) await _api.saveSelectedChild(children.first.id);
      await _loadSelected(version);
    } catch (error) {
      if (!_isCurrent(version)) return;
      await _api.logout();
      if (_isCurrent(version)) {
        state = AppState(
          error: error.toString().replaceFirst('Exception: ', ''),
        );
      }
      rethrow;
    }
  }

  Future<void> selectChild(Child child) async {
    final selected = state.children
        .where((item) => item.id == child.id)
        .firstOrNull;
    if (selected == null || state.token == null) return;
    final version = ++_requestVersion;
    state = state.copyWith(
      selectedChild: selected,
      posts: const [],
      projects: const [],
      loading: true,
      clearError: true,
    );
    await _api.saveSelectedChild(child.id);
    await _loadSelected(version);
  }

  Future<void> refresh() async {
    final token = state.token;
    if (token == null) return;
    final selectedId = state.selectedChild?.id;
    final version = ++_requestVersion;
    state = state.copyWith(
      posts: const [],
      projects: const [],
      loading: true,
      clearError: true,
    );
    try {
      // Os vínculos podem ter sido alterados pela coordenação desde o login.
      final children = await _api.getChildren(token);
      if (!_isCurrent(version)) return;
      final selected =
          children.where((item) => item.id == selectedId).firstOrNull ??
          children.firstOrNull;
      state = AppState(
        token: token,
        children: children,
        selectedChild: selected,
        loading: selected != null,
        error: selected == null
            ? 'Nenhum aluno está vinculado a esta conta. Consulte a escola.'
            : null,
      );
      if (selected != null) {
        await _api.saveSelectedChild(selected.id);
        await _loadSelected(version);
      }
    } catch (error) {
      if (_isCurrent(version)) {
        state = AppState(
          token: token,
          error: error.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  Future<void> _loadSelected(int version) async {
    if (!_isCurrent(version)) return;
    final token = state.token;
    final child = state.selectedChild;
    if (token == null || child == null) return;
    try {
      final posts = await _api.getPosts(token, child.id);
      if (!_isCurrent(version)) return;
      final projects = await _api.getProjects(token, child.id);
      if (!_isCurrent(version)) return;
      state = state.copyWith(
        posts: posts,
        projects: projects,
        loading: false,
        clearError: true,
      );
    } catch (error) {
      if (!_isCurrent(version)) return;
      state = state.copyWith(
        posts: const [],
        projects: const [],
        loading: false,
        error: error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> logout() async {
    ++_requestVersion;
    state = const AppState();
    await _api.logout();
  }
}

final apiProvider = Provider((ref) => TinhaKidsApiService());
final appProvider = StateNotifierProvider<AppNotifier, AppState>(
  (ref) => AppNotifier(ref.read(apiProvider)),
);
