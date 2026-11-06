"""Run cosmetic or World FFA match stress checks on a private Roblox version."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
UNIVERSE, PLACE = '10774039150', '129521354706128'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--key-file', type=Path, required=True)
    parser.add_argument('--version', type=int, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--matches', action='store_true', help='Run mixed and human-only World FFA joins and expansion.')
    args = parser.parse_args()
    assert args.version > 0
    key = args.key_file.read_text(encoding='utf-8-sig').strip()

    def call(path, body=None):
        request = urllib.request.Request('https://apis.roblox.com/cloud/v2/' + path,
            data=json.dumps(body).encode() if body else None,
            headers={'x-api-key': key, 'Content-Type': 'application/json'})
        for attempt in range(6):
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    return json.load(response)
            except urllib.error.HTTPError as error:
                if error.code != 429 or attempt == 5:
                    raise
                delay = error.headers.get('Retry-After', '')
                time.sleep(max(1, int(delay)) if delay.isdigit() else 8)

    universe = call('universes/' + UNIVERSE)
    assert universe['visibility'] == 'PRIVATE' and universe['user'] == 'users/8318659852'
    assert universe['rootPlace'] == f'universes/{UNIVERSE}/places/{PLACE}'
    args.output.mkdir(parents=True, exist_ok=True)

    def run(case):
        name, file, variables = case
        script = f'assert(game.PlaceVersion == {args.version})\n'
        for key, value in variables.items():
            script += f'local STRESS_{key} = {value}\n'
        script += (ROOT / 'tools/frontier' / file).read_text(encoding='utf-8')
        record = call(f'universes/{UNIVERSE}/places/{PLACE}/versions/{args.version}/luau-execution-session-tasks',
            {'script': script, 'timeout': '120s'})
        destination = args.output / (name + '.json')
        for _ in range(100):
            destination.write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
            if record['state'] not in ('QUEUED', 'PROCESSING'):
                assert record['state'] == 'COMPLETE', f'{name} failed: see {destination}'
                print(name + ': COMPLETE', flush=True)
                return
            time.sleep(2)
            record = call(record['path'])
        raise TimeoutError(f'{name} still pending; resume the task recorded in {destination}')

    if args.matches:
        cases = [('match-1', 'check_match_stress.luau', dict(PLAYERS=1, WIDTH=844, HEIGHT=390)),
                 ('match-19', 'check_match_stress.luau', dict(PLAYERS=19, WIDTH=1920, HEIGHT=1080)),
                 ('match-20', 'check_match_stress.luau', dict(PLAYERS=20, WIDTH=1920, HEIGHT=1080)),
                 ('match-50', 'check_match_stress.luau', dict(PLAYERS=50, WIDTH=844, HEIGHT=390)),
                 ('match-50-long', 'check_match_stress.luau', dict(PLAYERS=50, TICKS=900, WIDTH=1920, HEIGHT=1080))]
    else:
        cases = [('phone', 'check_cosmetic_stress.luau', dict(WIDTH=844, HEIGHT=390)),
                 ('desktop', 'check_cosmetic_stress.luau', dict(WIDTH=1920, HEIGHT=1080)),
                 ('4k', 'check_cosmetic_stress.luau', dict(WIDTH=3840, HEIGHT=2160)),
                 ('flags', 'check_cosmetic_flags.luau', {})]
    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(run, cases))
    assert call('universes/' + UNIVERSE)['visibility'] == 'PRIVATE'


if __name__ == '__main__':
    main()
