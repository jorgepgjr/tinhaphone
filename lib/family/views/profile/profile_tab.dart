import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/post.dart';
import '../../providers/app_state.dart';

class _ProfilePhoto {
  final String url;
  final DateTime date;
  final String caption;
  const _ProfilePhoto(this.url, this.date, this.caption);
}

class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  bool _separateByYear = true;
  int? _selectedYear;

  List<_ProfilePhoto> _photos(List<Post> posts) => posts
      .expand(
        (post) => (post.imageUrls.isEmpty ? [post.imageUrl] : post.imageUrls)
            .map((url) => _ProfilePhoto(url, post.createdAt, post.caption)),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final child = state.selectedChild;
    final allPhotos = _photos(state.posts);
    final years = allPhotos.map((photo) => photo.date.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final visible = _selectedYear == null
        ? allPhotos
        : allPhotos.where((photo) => photo.date.year == _selectedYear).toList();
    final groups = <int, List<_ProfilePhoto>>{};
    for (final photo in visible) {
      groups.putIfAbsent(photo.date.year, () => []).add(photo);
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(appProvider.notifier).refresh(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundImage: child?.avatarUrl.isNotEmpty == true
                            ? NetworkImage(child!.avatarUrl)
                            : null,
                        child: child?.avatarUrl.isNotEmpty == true
                            ? null
                            : Text(
                                child?.name.substring(0, 1).toUpperCase() ??
                                    '?',
                                style: const TextStyle(fontSize: 28),
                              ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              child?.name ?? 'Perfil',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              child?.classroom ?? '',
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _Stat(value: '${allPhotos.length}', label: 'fotos'),
                      _Stat(
                        value: '${state.posts.length}',
                        label: 'publicações',
                      ),
                      _Stat(
                        value: '${state.projects.length}',
                        label: 'projetos',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: state.children
                          .map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(item.name),
                                selected: item.id == child?.id,
                                onSelected: (_) => ref
                                    .read(appProvider.notifier)
                                    .selectChild(item),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(
                          Icons.calendar_month_outlined,
                          size: 16,
                        ),
                        label: const Text('Por ano'),
                        selected: _separateByYear,
                        onSelected: (value) =>
                            setState(() => _separateByYear = value),
                      ),
                      if (years.length > 1) ...[
                        const SizedBox(width: 8),
                        PopupMenuButton<int?>(
                          tooltip: 'Filtrar ano',
                          initialValue: _selectedYear,
                          onSelected: (value) =>
                              setState(() => _selectedYear = value),
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: null,
                              child: Text('Todos os anos'),
                            ),
                            ...years.map(
                              (year) => PopupMenuItem(
                                value: year,
                                child: Text('$year'),
                              ),
                            ),
                          ],
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _selectedYear?.toString() ?? 'Todos',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const Icon(Icons.arrow_drop_down, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (state.loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (visible.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'As fotos publicadas aparecerão neste perfil.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          else if (_separateByYear)
            ...groups.entries.expand(
              (entry) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                    child: Text(
                      '${entry.key}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                _PhotoGrid(photos: entry.value),
              ],
            )
          else
            _PhotoGrid(photos: visible),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    ),
  );
}

class _PhotoGrid extends StatelessWidget {
  final List<_ProfilePhoto> photos;
  const _PhotoGrid({required this.photos});

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    sliver: SliverGrid.builder(
      itemCount: photos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemBuilder: (context, index) {
        final photo = photos[index];
        return InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => Dialog(
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Image.network(
                      photo.url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined, size: 42),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(photo.caption),
                        const SizedBox(height: 6),
                        Text(
                          '${photo.date.day.toString().padLeft(2, '0')}/${photo.date.month.toString().padLeft(2, '0')}/${photo.date.year}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          child: Image.network(
            photo.url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: Color(0xFFE2E8F0),
              child: Icon(Icons.broken_image_outlined),
            ),
          ),
        );
      },
    ),
  );
}
