import 'package:flutter/material.dart';

import 'cycle.dart';

const monthsNom = [
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
];
const monthsGen = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
];
const weekdaysShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

String fmtDate(DateTime d, {bool year = false}) =>
    '${d.day} ${monthsGen[d.month - 1]}${year ? ' ${d.year}' : ''}';

String plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

String daysWord(int n) => '$n ${plural(n, 'день', 'дня', 'дней')}';

class Palette {
  static const period = Color(0xFFE53950);
  static const predicted = Color(0xFFF59AAA);
  static const fertile = Color(0xFF8EC5EE);
  static const ovulation = Color(0xFF2F80C9);
}

Color? kindColor(DayKind k) => switch (k) {
      DayKind.period => Palette.period,
      DayKind.predicted => Palette.predicted,
      DayKind.fertile => Palette.fertile,
      DayKind.ovulation => Palette.ovulation,
      DayKind.none => null,
    };
