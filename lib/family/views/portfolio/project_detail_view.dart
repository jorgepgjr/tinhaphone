import 'package:flutter/material.dart';
import '../../core/models/project.dart';
import '../../core/theme/app_theme.dart';

class ProjectDetailView extends StatelessWidget {
  final Project project;

  const ProjectDetailView({Key? key, required this.project}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Banner Sliver AppBar with Hero Image
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            stretch: true,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: Colors.white.withOpacity(0.9),
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: AppColors.textPrimary,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            backgroundColor: AppColors.background,
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.blurBackground,
              ],
              background: Hero(
                tag: 'project_image_${project.id}',
                child: _ProjectGallery(project: project),
              ),
            ),
          ),

          // Project Description & Objectives Content
          SliverToBoxAdapter(
            child: Container(
              transform: Matrix4.translationValues(0, -20, 0),
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 24.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Main Title & Date Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'PROJETO ESCOLAR',
                              style: textTheme.bodyMedium?.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            project.title,
                            style: textTheme.titleLarge?.copyWith(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                size: 14,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Concluído em ${project.completionDate}',
                                style: textTheme.bodyMedium?.copyWith(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Description Block
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Resumo da Atividade',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            project.description,
                            style: textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              height: 1.5,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Pedagogical Objectives Block
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.verified_rounded,
                                color: AppColors.secondary,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Objetivos Pedagógicos',
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ...project.pedagogicalObjectives.map(
                            (objective) => Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 2),
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: AppColors.secondaryLight,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.done_rounded,
                                      size: 12,
                                      color: AppColors.secondary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      objective,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: AppColors.textPrimary,
                                        fontSize: 13.5,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectGallery extends StatefulWidget {
  final Project project;

  const _ProjectGallery({required this.project});

  @override
  State<_ProjectGallery> createState() => _ProjectGalleryState();
}

class _ProjectGalleryState extends State<_ProjectGallery> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final images = widget.project.imageUrls.isEmpty
        ? [widget.project.imageUrl]
        : widget.project.imageUrls;
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          itemCount: images.length,
          onPageChanged: (value) => setState(() => _page = value),
          itemBuilder: (context, index) => Image.network(
            images[index],
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: Color(0xFFE2E8F0),
              child: Center(child: Icon(Icons.broken_image_outlined, size: 40)),
            ),
          ),
        ),
        if (images.length > 1)
          Positioned(
            right: 16,
            bottom: 34,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                child: Text(
                  '${_page + 1}/${images.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
