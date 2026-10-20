import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/tinha_brand.dart';
import '../../core/models/child.dart';
import '../../core/models/post.dart';
import '../../providers/app_state.dart';

const _secondary = Color(0xFF535E7A);
const _soft = Color(0xFF7A87A3);

class FeedTab extends ConsumerWidget {
  const FeedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final selected = state.selectedChild;
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = constraints.maxWidth > 654
            ? (constraints.maxWidth - 620) / 2
            : 17.0;
        return RefreshIndicator(
          color: tinhaBlue,
          onRefresh: () => ref.read(appProvider.notifier).refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(inset + 6, 18, inset + 6, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Publicações',
                        style: TextStyle(
                          fontSize: 30,
                          height: 1.2,
                          fontWeight: FontWeight.w900,
                          color: tinhaNavy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Momentos compartilhados pela escola.',
                        style: TextStyle(
                          color: _secondary,
                          fontSize: 16,
                          height: 1.35,
                        ),
                      ),
                      if (state.children.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: state.children
                                .map(
                                  (child) => Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: _ChildSelector(
                                      child: child,
                                      selected: selected?.id == child.id,
                                      onTap: () {
                                        if (selected?.id != child.id) {
                                          ref
                                              .read(appProvider.notifier)
                                              .selectChild(child);
                                        }
                                      },
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (state.loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(color: tinhaBlue),
                  ),
                )
              else if (state.error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Empty(
                    icon: state.children.isEmpty
                        ? Icons.school_outlined
                        : Icons.cloud_off_outlined,
                    title:
                        state.children.isEmpty &&
                            state.error!.startsWith('Nenhum aluno')
                        ? 'Vamos acompanhar juntos?'
                        : 'Não foi possível atualizar',
                    text: state.error!,
                    onRetry: () => ref.read(appProvider.notifier).refresh(),
                  ),
                )
              else if (state.posts.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Empty(
                    icon: Icons.photo_library_outlined,
                    title: 'Nenhuma publicação ainda',
                    text:
                        'As novas fotos de ${selected?.name ?? 'seu filho'} aparecerão aqui.',
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(inset, 0, inset, 18),
                  sliver: SliverList.separated(
                    itemCount: state.posts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 18),
                    itemBuilder: (context, index) => _PostCard(
                      key: ValueKey('${selected?.id}:${state.posts[index].id}'),
                      post: state.posts[index],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ChildSelector extends StatelessWidget {
  final Child child;
  final bool selected;
  final VoidCallback onTap;
  const _ChildSelector({
    required this.child,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? const Color(0xFFE7EFFF) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          color: selected ? const Color(0xFFA8BCFF) : const Color(0xFFE7EDF6),
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Avatar(
                url: child.avatarUrl,
                name: child.name,
                radius: 15.5,
                selected: selected,
              ),
              const SizedBox(width: 11),
              Text(
                child.name,
                style: TextStyle(
                  fontSize: 15,
                  color: selected ? tinhaNavy : _secondary,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              const SizedBox(width: 3),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PostCard extends StatefulWidget {
  final Post post;
  const _PostCard({super.key, required this.post});

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  final _controller = PageController();
  int _page = 0;
  Post get post => widget.post;
  List<String> get images =>
      post.imageUrls.isEmpty ? [post.imageUrl] : post.imageUrls;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_page >= images.length) {
      _page = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
    }
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} às ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  void _goTo(int page) => _controller.animateToPage(
    page,
    duration: const Duration(milliseconds: 240),
    curve: Curves.easeOut,
  );

  void _showDetails() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Informações da publicação',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: tinhaNavy,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar informações',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: _secondary),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F6FF),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    _Avatar(
                      url: post.teacherAvatarUrl,
                      name: post.teacherName,
                      radius: 24,
                      teacher: true,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Compartilhado por',
                            style: TextStyle(fontSize: 12, color: _secondary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            post.teacherName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: tinhaNavy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _detailRow(Icons.groups_outlined, 'Turma', post.classroomName),
              _detailRow(
                Icons.calendar_today_outlined,
                'Publicado em',
                _date(post.createdAt.toLocal()),
              ),
              _detailRow(
                Icons.photo_library_outlined,
                'Fotografias',
                '${images.length} ${images.length == 1 ? 'foto' : 'fotos'}',
              ),
              if (post.caption.trim().isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: Color(0xFFE4EAF4)),
                ),
                const Text(
                  'Sobre este momento',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _secondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  post.caption,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: tinhaNavy,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _detailRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: tinhaBlue, size: 21),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: _soft)),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: tinhaNavy,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A6F96C6),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 17, 10, 13),
          child: Row(
            children: [
              _Avatar(
                url: post.teacherAvatarUrl,
                name: post.teacherName,
                radius: 23,
                teacher: true,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.teacherName,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        color: tinhaNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${post.classroomName} · ${_date(post.createdAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        color: _soft,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Informações da publicação',
                onPressed: _showDetails,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 48),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert_rounded, color: _soft),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: AspectRatio(
              aspectRatio: 1.56,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _controller,
                    itemCount: images.length,
                    onPageChanged: (value) => setState(() => _page = value),
                    itemBuilder: (context, index) => images[index].isEmpty
                        ? const _PhotoUnavailable()
                        : Image.network(
                            images[index],
                            fit: BoxFit.cover,
                            width: double.infinity,
                            loadingBuilder: (context, child, progress) =>
                                progress == null
                                ? child
                                : const ColoredBox(
                                    color: Color(0xFFEDF3FC),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: tinhaBlue,
                                      ),
                                    ),
                                  ),
                            errorBuilder: (_, _, _) =>
                                const _PhotoUnavailable(),
                          ),
                  ),
                  if (images.length > 1) ...[
                    Positioned(
                      top: 10,
                      right: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xB32A3445),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Semantics(
                            liveRegion: true,
                            label: 'Foto ${_page + 1} de ${images.length}',
                            child: Text(
                              '${_page + 1}/${images.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _PhotoArrow(
                          previous: true,
                          onTap: () => _goTo(
                            (_page - 1 + images.length) % images.length,
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _PhotoArrow(
                          onTap: () => _goTo((_page + 1) % images.length),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (images.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Wrap(
              alignment: WrapAlignment.center,
              children: List.generate(
                images.length,
                (index) => Semantics(
                  selected: index == _page,
                  label: 'Ir para foto ${index + 1}',
                  button: true,
                  child: InkResponse(
                    onTap: () => _goTo(index),
                    child: SizedBox(
                      width: 17,
                      height: 24,
                      child: Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index == _page
                                ? tinhaBlue
                                : const Color(0xFFD9E2F2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          const SizedBox(height: 14),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 17),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE0E7F2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 15, 18, 20),
          child: Text(
            post.caption,
            style: const TextStyle(fontSize: 15, height: 1.4, color: tinhaNavy),
          ),
        ),
      ],
    ),
  );
}

class _PhotoArrow extends StatelessWidget {
  final bool previous;
  final VoidCallback onTap;
  const _PhotoArrow({this.previous = false, required this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: previous ? 'Foto anterior' : 'Próxima foto',
    onPressed: onTap,
    style: IconButton.styleFrom(
      minimumSize: const Size.square(36),
      padding: const EdgeInsets.all(3),
      backgroundColor: const Color(0x80424A58),
      foregroundColor: Colors.white,
      side: const BorderSide(color: Color(0xBFFFFFFF)),
    ),
    icon: Icon(
      previous ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
      size: 26,
    ),
  );
}

class _PhotoUnavailable extends StatelessWidget {
  const _PhotoUnavailable();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFFEAF0FA),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported_outlined, size: 36, color: _soft),
          SizedBox(height: 8),
          Text('Foto indisponível', style: TextStyle(color: _secondary)),
        ],
      ),
    ),
  );
}

class _Avatar extends StatelessWidget {
  final String url;
  final String name;
  final double radius;
  final bool selected;
  final bool teacher;
  const _Avatar({
    required this.url,
    required this.name,
    required this.radius,
    this.selected = false,
    this.teacher = false,
  });

  @override
  Widget build(BuildContext context) {
    final initial = Center(
      child: Text(
        name.trim().characters.firstOrNull?.toUpperCase() ?? '?',
        style: TextStyle(
          fontSize: teacher ? 20 : 16,
          fontWeight: FontWeight.w800,
          color: selected
              ? Colors.white
              : (teacher ? const Color(0xFF334FA7) : const Color(0xFF3C4866)),
        ),
      ),
    );
    return ClipOval(
      child: SizedBox.square(
        dimension: radius * 2,
        child: ColoredBox(
          color: selected
              ? tinhaBlue
              : (teacher ? const Color(0xFFD4DBFF) : const Color(0xFFD6DDEB)),
          child: url.isEmpty
              ? initial
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => initial,
                ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback? onRetry;
  const _Empty({
    required this.icon,
    required this.title,
    required this.text,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: const Color(0xFF9BAED0)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: tinhaNavy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _secondary),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Atualizar'),
            ),
          ],
        ],
      ),
    ),
  );
}
