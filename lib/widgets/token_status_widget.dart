import 'package:flutter/material.dart';
import '../services/neon_auth_service.dart';

/// Debug-Widget das den Token-Status anzeigt
class TokenStatusWidget extends StatefulWidget {
  final NeonAuthService authService;
  
  const TokenStatusWidget({
    super.key,
    required this.authService,
  });

  @override
  State<TokenStatusWidget> createState() => _TokenStatusWidgetState();
}

class _TokenStatusWidgetState extends State<TokenStatusWidget> {
  @override
  void initState() {
    super.initState();
    // Update jede Minute
    _startPeriodicUpdate();
  }
  
  void _startPeriodicUpdate() {
    Future.delayed(const Duration(minutes: 1), () {
      if (mounted) {
        setState(() {});
        _startPeriodicUpdate();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authService.isLoggedIn) {
      return const SizedBox.shrink();
    }
    
    final expiration = widget.authService.tokenExpirationDate;
    final timeLeft = widget.authService.timeUntilTokenExpiry;
    final isExpiringSoon = widget.authService.isTokenExpiringSoon;
    
    if (expiration == null || timeLeft == null) {
      return const SizedBox.shrink();
    }
    
    final color = isExpiringSoon ? Colors.orange : Colors.green;
    final icon = isExpiringSoon ? Icons.warning : Icons.check_circle;
    
    return Card(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Text(
              'Token läuft ab in: ${_formatDuration(timeLeft)}',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (isExpiringSoon) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  await widget.authService.refreshToken();
                  if (mounted) setState(() {});
                },
                child: const Text('Refresh', style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  String _formatDuration(Duration duration) {
    if (duration.isNegative) return 'Abgelaufen';
    
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }
}

