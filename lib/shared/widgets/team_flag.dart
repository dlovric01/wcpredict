import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:wcpredict/core/models/team_model.dart';

/// Circular flag image for a team. Falls back to a CircleAvatar with the
/// team code when the image cannot be loaded.
class TeamFlag extends StatelessWidget {
  const TeamFlag({super.key, required this.team, this.size = 32.0});

  final TeamModel team;
  final double size;

  @override
  Widget build(BuildContext context) {
    final flagUrl = team.flagUrl;
    if (flagUrl != null && flagUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: flagUrl,
        width: size,
        height: size,
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: size / 2,
          backgroundImage: imageProvider,
        ),
        errorWidget: (context, url, error) => _fallback(context),
        placeholder: (context, url) => _fallback(context),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        team.code,
        style: TextStyle(
          fontSize: size * 0.3,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
