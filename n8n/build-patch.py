# -*- coding: utf-8 -*-
"""Wrap the two replacement nodes in a workflow envelope n8n will accept.

n8n's importer and canvas-paste both require {"nodes": [...], "connections": {...}}.
A bare node object is rejected with "The imported data does not contain valid
workflow data ('nodes' and 'connections' are missing)".

Generated rather than hand-written because the Code node's jsCode has to become a
single JSON string with every newline and quote escaped. Doing that by hand is
how you get a file that imports cleanly and then runs broken code.

Run from the repo root:  python n8n/build-patch.py
"""
import io
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
GEMINI_SRC = os.path.join(HERE, 'ai-validation-ocr-omr.node.json')
JS_SRC = os.path.join(HERE, 'reconcile-ocr-omr.js')
OUT = os.path.join(HERE, 'patch-ocr-omr-reconciliation.json')


def build():
    # ── the Gemini node, minus the non-standard _comment key ────────────────
    with io.open(GEMINI_SRC, encoding='utf-8') as fh:
        gemini = json.load(fh)

    gemini['notes'] = '\n'.join(gemini.pop('_comment'))
    gemini['notesInFlow'] = False

    # ── the reconciler, with the .js file as its jsCode ─────────────────────
    with io.open(JS_SRC, encoding='utf-8') as fh:
        js = fh.read()

    reconcile = {
        'parameters': {'jsCode': js},
        'type': 'n8n-nodes-base.code',
        'typeVersion': 2,
        'position': [-6496, -1056],
        'id': 'a1c4e7b2-5d31-4f88-9e02-6b7c1d4a9f30',
        'name': 'reconcile ocr and omr',
        'notes': (
            'Replaces "separate it", which could never work: it read\n'
            'item.json.choices[0].message.content -- the OpenAI response shape --\n'
            "while the node calls Google's generateContent, which returns\n"
            'candidates[0].content.parts[0].text. Its own try/catch swallowed the\n'
            'throw, so the scan path produced empty OCR data silently.\n\n'
            'OCR fields  -> Gemini wins (Python OCR is unreliable)\n'
            'OMR scores  -> Python wins (never overridden, only blank-filled)\n\n'
            'Flags for SAO review when 5+ of 20 differ by 2 or more, or more than\n'
            '10 of 20 are blank with both engines agreeing.'
        ),
        'notesInFlow': False,
    }

    envelope = {
        'name': 'iEvaluate - OCR/OMR reconciliation patch',
        'nodes': [gemini, reconcile],
        'connections': {
            'ai validation ocr and omr': {
                'main': [[{'node': 'reconcile ocr and omr', 'type': 'main', 'index': 0}]]
            }
        },
        'pinData': {},
        'settings': {'executionOrder': 'v1'},
    }

    with io.open(OUT, 'w', encoding='utf-8', newline='\n') as fh:
        json.dump(envelope, fh, indent=2, ensure_ascii=False)

    return js


def verify(js):
    """Prove the file is importable before claiming it is."""
    with io.open(OUT, encoding='utf-8') as fh:
        check = json.load(fh)

    assert isinstance(check.get('nodes'), list), 'nodes must be a list'
    assert isinstance(check.get('connections'), dict), 'connections must be an object'
    assert len(check['nodes']) == 2, check['nodes']

    names = [n['name'] for n in check['nodes']]
    assert names == ['ai validation ocr and omr', 'reconcile ocr and omr'], names

    assert '_comment' not in json.dumps(check), 'non-standard key survived'

    # The embedded code must round-trip to exactly the source file, or the node
    # runs something other than what was reviewed.
    assert check['nodes'][1]['parameters']['jsCode'] == js, 'jsCode did not round-trip'

    # The Gemini jsonBody is an n8n expression wrapping JSON. Strip the leading
    # '=' and substitute the {{ }} placeholder, then it must parse.
    body = check['nodes'][0]['parameters']['jsonBody']
    assert body.startswith('={'), body[:20]
    probe = body[1:].replace(
        "{{ $('SAST image from phone').item.json.body.image }}", 'X')
    json.loads(probe)

    return names, len(js)


if __name__ == '__main__':
    source = build()
    node_names, size = verify(source)
    print('wrote', OUT)
    print('nodes:', node_names)
    print('jsCode bytes:', size)
