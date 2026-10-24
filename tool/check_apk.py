#!/usr/bin/env python3
"""Static sanity checks on a packaged release APK (stdlib only).

Parses the merged binary AndroidManifest.xml and the class definitions of
every classes*.dex, then asserts:

* the <application> class and the launcher activity class are defined in dex;
* every component class named in the manifest (activity, activity-alias,
  service, receiver, provider) is defined in dex, unless its package is on
  the third-party whitelist below (framework/library components whose
  classes are not expected under an app-owned descriptor);
* Lgo/Seq; is defined exactly once across all dex files (the two gomobile
  runtimes must share a single Seq copy);
* libclash.so and libbox.so coexist under every lib/<abi>/ directory.

Usage: check_apk.py <apk> [<apk> ...]
Exit code 0 = all checks passed, 1 = at least one failure.
"""

import struct
import sys
import zipfile

ANDROID_NS = "http://schemas.android.com/apk/res/android"

# Packages whose manifest components are provided by the framework or by
# libraries that ship their own dex; anything outside this list and outside
# the APK's own defined types is reported as a missing class.
THIRD_PARTY_PREFIXES = (
    "android.",
    "androidx.",
    "com.android.",
    "com.google.android.",
    "com.google.firebase.",
    "dev.fluttercommunity.",
    "io.flutter.",
    "kotlin.",
    "kotlinx.",
)


def _u16(buf, off):
    return struct.unpack_from("<H", buf, off)[0]


def _u32(buf, off):
    return struct.unpack_from("<I", buf, off)[0]


class StringPool:
    def __init__(self, buf, off):
        self.strings = []
        header_size = _u16(buf, off + 2)
        count = _u32(buf, off + 8)
        flags = _u32(buf, off + 16)
        strings_start = _u32(buf, off + 20)
        utf8 = bool(flags & 0x100)
        offsets = [_u32(buf, off + header_size + 4 * i) for i in range(count)]
        base = off + strings_start
        for rel in offsets:
            pos = base + rel
            if utf8:
                _, used = self._len8(buf, pos)
                pos += used
                byte_len, used = self._len8(buf, pos)
                pos += used
                raw = buf[pos:pos + byte_len]
                self.strings.append(raw.decode("utf-8", "replace"))
            else:
                char_len, used = self._len16(buf, pos)
                pos += used
                raw = buf[pos:pos + 2 * char_len]
                self.strings.append(raw.decode("utf-16-le", "replace"))

    @staticmethod
    def _len8(buf, pos):
        first = buf[pos]
        if first & 0x80:
            return ((first & 0x7F) << 8) | buf[pos + 1], 2
        return first, 1

    @staticmethod
    def _len16(buf, pos):
        first = _u16(buf, pos)
        if first & 0x8000:
            return ((first & 0x7FFF) << 16) | _u16(buf, pos + 2), 4
        return first, 2

    def get(self, idx):
        if idx == 0xFFFFFFFF or idx >= len(self.strings):
            return None
        return self.strings[idx]


def parse_manifest(data):
    """Return (package, application_name, [(kind, name, is_launcher)])."""
    if _u32(data, 0) & 0xFFFF != 0x0003:
        raise ValueError("not a binary XML file")
    pool = None
    package = None
    application_name = None
    components = []
    stack = []  # (tag, component record or None)
    off = 8
    while off + 8 <= len(data):
        chunk_type = _u16(data, off)
        chunk_size = _u32(data, off + 4)
        if chunk_size <= 0:
            break
        if chunk_type == 0x0001:  # string pool
            pool = StringPool(data, off)
        elif chunk_type == 0x0102:  # start element
            tag = pool.get(_u32(data, off + 20))
            attr_start = _u16(data, off + 24)
            attr_count = _u16(data, off + 28)
            attrs = {}
            for i in range(attr_count):
                aoff = off + 16 + attr_start + 20 * i
                ns = pool.get(_u32(data, aoff))
                name = pool.get(_u32(data, aoff + 4))
                raw = _u32(data, aoff + 8)
                data_type = data[aoff + 15]
                value_data = _u32(data, aoff + 16)
                if raw != 0xFFFFFFFF:
                    value = pool.get(raw)
                elif data_type == 0x03:  # TYPE_STRING
                    value = pool.get(value_data)
                else:
                    value = None
                attrs[(ns, name)] = value
            record = None
            if tag == "manifest":
                package = attrs.get((None, "package"))
            elif tag == "application":
                application_name = attrs.get((ANDROID_NS, "name"))
            elif tag in ("activity", "activity-alias", "service", "receiver", "provider"):
                record = {"kind": tag, "name": attrs.get((ANDROID_NS, "name")),
                          "actions": set(), "categories": set()}
                components.append(record)
            elif tag in ("action", "category"):
                owner = next((rec for _, rec in reversed(stack) if rec is not None), None)
                key = "actions" if tag == "action" else "categories"
                val = attrs.get((ANDROID_NS, "name"))
                if owner is not None and val:
                    owner[key].add(val)
            stack.append((tag, record))
        elif chunk_type == 0x0103:  # end element
            if stack:
                stack.pop()
        off += chunk_size
    result = []
    for rec in components:
        launcher = ("android.intent.action.MAIN" in rec["actions"]
                    and "android.intent.category.LAUNCHER" in rec["categories"])
        result.append((rec["kind"], rec["name"], launcher))
    return package, application_name, result


def dex_defined_types(data):
    if data[:4] != b"dex\n":
        raise ValueError("not a dex file")
    string_count = _u32(data, 0x38)
    string_off = _u32(data, 0x3C)
    type_count = _u32(data, 0x40)
    type_off = _u32(data, 0x44)
    class_count = _u32(data, 0x60)
    class_off = _u32(data, 0x64)

    def read_string(idx):
        pos = _u32(data, string_off + 4 * idx)
        # uleb128 utf16 length, not needed for ASCII descriptors
        shift = 0
        while True:
            byte = data[pos]
            pos += 1
            if not byte & 0x80:
                break
            shift += 7
        end = data.index(b"\x00", pos)
        return data[pos:end].decode("utf-8", "replace")

    type_desc = []
    for i in range(type_count):
        desc_idx = _u32(data, type_off + 4 * i)
        type_desc.append(read_string(desc_idx))
    defined = set()
    for i in range(class_count):
        class_idx = _u32(data, class_off + 32 * i)
        defined.add(type_desc[class_idx])
    _ = string_count
    return defined


def resolve(class_name, package):
    if class_name is None:
        return None
    if class_name.startswith("."):
        return package + class_name
    if "." not in class_name:
        return package + "." + class_name
    return class_name


def to_descriptor(class_name):
    return "L" + class_name.replace(".", "/") + ";"


def check_apk(path):
    errors = []
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        manifest_data = zf.read("AndroidManifest.xml")
        dex_types = set()
        seq_count = 0
        for name in names:
            base = name.rsplit("/", 1)[-1]
            if base.startswith("classes") and base.endswith(".dex"):
                defined = dex_defined_types(zf.read(name))
                dex_types |= defined
                seq_count += sum(1 for t in defined if t == "Lgo/Seq;")
        lib_dirs = {}
        for name in names:
            parts = name.split("/")
            if len(parts) == 3 and parts[0] == "lib":
                lib_dirs.setdefault(parts[1], set()).add(parts[2])

    package, app_name, components = parse_manifest(manifest_data)

    app_class = resolve(app_name, package)
    if app_class is None:
        errors.append("manifest declares no <application> class")
    elif to_descriptor(app_class) not in dex_types:
        errors.append(f"application class not defined in dex: {app_class}")

    launchers = [c for c in components if c[2]]
    if not launchers:
        errors.append("no launcher activity found in manifest")
    for kind, name, _ in components:
        fqcn = resolve(name, package)
        if fqcn is None:
            errors.append(f"{kind} without android:name")
            continue
        if fqcn.startswith(THIRD_PARTY_PREFIXES):
            continue
        if to_descriptor(fqcn) not in dex_types:
            errors.append(f"{kind} class not defined in dex: {fqcn}")

    if seq_count != 1:
        errors.append(f"Lgo/Seq; defined {seq_count} times across dex files, expected exactly 1")

    if not lib_dirs:
        errors.append("no lib/<abi>/ native libraries found")
    for abi, libs in sorted(lib_dirs.items()):
        for needed in ("libclash.so", "libbox.so"):
            if needed not in libs:
                errors.append(f"lib/{abi}/ is missing {needed}")
    return errors


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    failed = False
    for path in argv[1:]:
        errors = check_apk(path)
        if errors:
            failed = True
            print(f"FAIL {path}")
            for err in errors:
                print(f"  - {err}")
        else:
            print(f"OK   {path}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
