import 'package:flutter/material.dart';

Future<bool> showMobileConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  Color confirmColor = const Color(0xFFE31B23),
  Color confirmTextColor = Colors.white,
  IconData? icon,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: confirmColor),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(title)),
        ],
      ),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: confirmTextColor,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class MobilePageScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final double titleFontSize;

  const MobilePageScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions,
    this.floatingActionButton,
    this.titleFontSize = 30,
  });

  @override
  Widget build(BuildContext context) {
    final hasParentScaffold = Scaffold.maybeOf(context) != null;
    final content = Container(
      color: const Color(0xFFF6F3F0),
      child: Column(
        children: [
          _TopHero(
            title: title,
            subtitle: subtitle,
            actions: actions,
            titleFontSize: titleFontSize,
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: floatingActionButton == null ? 0 : 88),
              child: child,
            ),
          ),
        ],
      ),
    );

    if (hasParentScaffold) {
      return Stack(
        children: [
          Positioned.fill(child: content),
          if (floatingActionButton != null)
            Positioned(
              right: 16,
              bottom: 16,
              child: floatingActionButton!,
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F3F0),
      floatingActionButton: floatingActionButton,
      body: content,
    );
  }
}

class MobileHeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget>? trailing;

  const MobileHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitle.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE31B23), Color(0xFF8C0000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (hasSubtitle) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.92),
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...trailing!,
        ],
      ),
    );
  }
}

class MobileSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;
  final Color accentColor;

  const MobileSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.trailing,
    this.accentColor = const Color(0xFFE31B23),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: accentColor.withOpacity(0.12),
                    foregroundColor: accentColor,
                    child: Icon(icon, size: 18),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class MobileActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color accentColor;
  final Color? backgroundColor;

  const MobileActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
    this.accentColor = const Color(0xFFE31B23),
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitle.trim().isNotEmpty;
    return Card(
      color: backgroundColor,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        minVerticalPadding: 10,
        minLeadingWidth: 0,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: accentColor.withOpacity(0.14),
          foregroundColor: accentColor,
          child: Icon(icon),
        ),
        title: Text(
          title,
          maxLines: hasSubtitle ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: hasSubtitle
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : null,
        trailing: trailing ??
            Icon(
              Icons.chevron_right_rounded,
              color: accentColor,
            ),
        isThreeLine: hasSubtitle,
        onTap: onTap,
      ),
    );
  }
}

class MobileMetricChip extends StatelessWidget {
  final String label;
  const MobileMetricChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F3),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class MobileStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? caption;
  final IconData? icon;
  final Color accent;

  const MobileStatCard({
    super.key,
    required this.title,
    required this.value,
    this.caption,
    this.icon,
    this.accent = const Color(0xFFE31B23),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              CircleAvatar(
                radius: 18,
                backgroundColor: accent.withOpacity(0.12),
                foregroundColor: accent,
                child: Icon(icon, size: 18),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 6),
              Text(
                caption!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MobileStatusBadge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const MobileStatusBadge({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class MobileLabelValue extends StatelessWidget {
  final String label;
  final String value;

  const MobileLabelValue({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class MobileSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final VoidCallback? onSearch;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool showPrefixIcon;
  final bool showActionButton;

  const MobileSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onSearch,
    this.onSubmitted,
    this.onChanged,
    this.showPrefixIcon = true,
    this.showActionButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final showSearchAction = showActionButton && onSearch != null;
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        isDense: !showPrefixIcon && !showSearchAction,
        contentPadding: !showPrefixIcon && !showSearchAction
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 14)
            : null,
        prefixIcon: showPrefixIcon ? const Icon(Icons.search_rounded) : null,
        suffixIcon: showSearchAction
            ? IconButton(
                icon: const Icon(Icons.east_rounded),
                onPressed: onSearch,
              )
            : null,
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

class MobileEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const MobileEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: const Color(0xFFFFEBEE),
              foregroundColor: const Color(0xFFE31B23),
              child: Icon(icon, size: 30),
            ),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

class MobileRetryState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRetry;
  final String buttonLabel;

  const MobileRetryState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
    this.buttonLabel = 'Reload',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: const Color(0xFFFFEBEE),
              foregroundColor: const Color(0xFFE31B23),
              child: Icon(icon, size: 30),
            ),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE31B23),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopHero extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget>? actions;
  final double titleFontSize;

  const _TopHero({
    required this.title,
    required this.subtitle,
    this.actions,
    this.titleFontSize = 30,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final hasSubtitle = subtitle.trim().isNotEmpty;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE31B23), Color(0xFF8C0000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canPop)
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                )
              else
                const SizedBox(width: 48),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (hasSubtitle) ...[
                        const SizedBox(height: 6),
                        Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: 14)),
                      ],
                    ],
                  ),
                ),
              ),
              if (actions != null) ...actions!,
            ],
          ),
        ),
      ),
    );
  }
}
