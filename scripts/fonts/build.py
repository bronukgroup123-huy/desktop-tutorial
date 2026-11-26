"""Вбудовані шрифти застосунку (UI-004): статичні ваги Inter і Merriweather з офіційних змінних
шрифтів Google Fonts (SIL OFL 1.1), урізані до потрібних символів.

  curl -sSfLO 'https://raw.githubusercontent.com/google/fonts/main/ofl/inter/Inter%5Bopsz,wght%5D.ttf'
  curl -sSfLO 'https://raw.githubusercontent.com/google/fonts/main/ofl/merriweather/Merriweather%5Bopsz,wdth,wght%5D.ttf'
  pip install fonttools
  python3 scripts/fonts/build.py <тека зі змінними шрифтами> flutter_client/assets/fonts

Inter — 400…900 (текст інтерфейсу: латиниця, кирилиця, знаки, стрілки, ₴, №);
Merriweather — 400 і 700 (заголовки: латиниця, українська кирилиця, пунктуація), без хінтингу.
"""
import pathlib
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

NAMES = {400: 'Regular', 500: 'Medium', 600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold', 900: 'Black'}
FONTS = {
    'Inter': {
        'src': 'Inter[opsz,wght].ttf',
        'axes': {'opsz': 14},
        'weights': [400, 500, 600, 700, 800, 900],
        'unicodes': 'U+0020-007E,U+00A0-00FF,U+0100-017F,U+0400-04FF,U+2000-206F,U+20A0-20CF,U+2100-214F,'
                    'U+2190-21FF,U+2200-22FF,U+2460-24FF,U+25A0-25FF',
    },
    'Merriweather': {
        'src': 'Merriweather[opsz,wdth,wght].ttf',
        'axes': {'opsz': 18, 'wdth': 100},
        'weights': [400, 700],
        'unicodes': 'U+0020-007E,U+00A0-00FF,U+0400-045F,U+0490-0491,U+2010-2027,U+2030-203A,U+20B4,U+2116,U+2122',
    },
}


def build(src_dir: pathlib.Path, out_dir: pathlib.Path) -> None:
    for family, spec in FONTS.items():
        for weight in spec['weights']:
            font = instancer.instantiateVariableFont(TTFont(src_dir / spec['src']), spec['axes'] | {'wght': weight},
                                                     updateFontNames=True)
            opts = subset.Options()
            opts.layout_features = ['*']
            opts.name_IDs = ['*']
            opts.notdef_outline = True
            opts.hinting = False
            sub = subset.Subsetter(opts)
            sub.populate(unicodes=subset.parse_unicodes(spec['unicodes']))
            sub.subset(font)
            out = out_dir / f'{family}-{NAMES[weight]}.ttf'
            font.save(out)
            print(out, out.stat().st_size)


if __name__ == '__main__':
    build(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
