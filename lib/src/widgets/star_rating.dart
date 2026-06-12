import 'package:flutter/material.dart';

/// Compact read-only rating: a star, the average, and an optional count.
class StarRating extends StatelessWidget {
  const StarRating({
    required this.rating,
    super.key,
    this.size = 16,
    this.count,
  });
  final double rating;
  final double size;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: size + 2, color: Colors.amber),
        const SizedBox(width: 2),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(fontSize: size * 0.9, fontWeight: FontWeight.w600),
        ),
        if (count != null) ...[
          const SizedBox(width: 3),
          Text(
            '($count)',
            style: TextStyle(fontSize: size * 0.8, color: Colors.grey),
          ),
        ],
      ],
    );
  }
}

/// A tappable 1–5 star input.
class StarInput extends StatelessWidget {
  const StarInput({
    required this.value,
    required this.onChanged,
    super.key,
    this.size = 36,
  });
  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < value;
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(
            filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: Colors.amber,
          ),
          onPressed: () => onChanged(i + 1),
        );
      }),
    );
  }
}
