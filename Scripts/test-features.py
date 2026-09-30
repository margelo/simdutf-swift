#!/usr/bin/env python3
"""Test trait configurations and prove disabled APIs are absent from binaries."""

import argparse
import pathlib
import re
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
FEATURES = {"UTF8", "UTF16", "UTF32", "ASCII", "Latin1", "Base64", "DetectEncoding"}
DEFAULTS = {"UTF8", "UTF16"}

# Include both single-feature APIs and APIs requiring two enabled encodings.
# Tuple: required traits, public Swift/C function, upstream C++ function.
PROBES = [
    ({"UTF8"}, "simdutf_validate_utf8_with_errors", "validate_utf8_with_errors"),
    ({"UTF16"}, "simdutf_validate_utf16_with_errors", "validate_utf16_with_errors"),
    ({"UTF32"}, "simdutf_validate_utf32_with_errors", "validate_utf32_with_errors"),
    ({"ASCII"}, "simdutf_validate_ascii", "validate_ascii"),
    ({"Base64"}, "simdutf_binary_to_base64", "binary_to_base64"),
    ({"DetectEncoding"}, "simdutf_detect_encodings", "detect_encodings"),
    ({"Latin1", "UTF8"}, "simdutf_convert_latin1_to_utf8", "convert_latin1_to_utf8"),
    ({"Latin1", "UTF16"}, "simdutf_convert_latin1_to_utf16", "convert_latin1_to_utf16"),
    ({"Latin1", "UTF32"}, "simdutf_convert_latin1_to_utf32", "convert_latin1_to_utf32"),
    ({"UTF8", "UTF16"}, "simdutf_convert_utf16_to_utf8_with_replacement", "convert_utf16_to_utf8_with_replacement"),
    ({"UTF8", "UTF32"}, "simdutf_convert_utf32_to_utf8", "convert_utf32_to_utf8"),
    ({"UTF16", "UTF32"}, "simdutf_convert_utf32_to_utf16", "convert_utf32_to_utf16"),
    ({"UTF8", "UTF16"}, "simdutf_swift_utf16_to_utf8", None),
    ({"UTF8", "UTF16"}, "simdutf_swift_valid_utf8_to_utf16", None),
    ({"UTF16"}, "simdutf_swift_validate_utf16", None),
    ({"UTF16"}, "simdutf_swift_repair_utf16", None),
]


def run(arguments, *, check=True):
    result = subprocess.run(arguments, cwd=ROOT, text=True, capture_output=True)
    if check and result.returncode:
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise RuntimeError(f"Command failed: {' '.join(map(str, arguments))}")
    return result


def enabled_traits(traits):
    enabled = DEFAULTS.copy() if traits is None else set(traits)
    if "All" in enabled:
        enabled.update(FEATURES)
    if "DetectEncoding" in enabled:
        enabled.update({"UTF8", "UTF16", "UTF32"})
    return enabled


def build_arguments(traits, configuration):
    # The native backend is supported by Swift 6.1 and gives consistent module
    # and object locations on both Darwin and Linux, including newer toolchains
    # where Swift Build has become the default backend.
    arguments = ["--build-system", "native", "--configuration", configuration]
    if traits is not None:
        arguments += ["--disable-default-traits"]
        if traits:
            arguments += ["--traits", ",".join(traits)]
    return arguments


def defined_symbols(bin_path):
    object_directory = bin_path / "CSimdUTF.build"
    objects = sorted(object_directory.rglob("*.o"))
    if not objects:
        raise RuntimeError(f"No C++ objects found in {object_directory}")
    result = run(["nm", "-g", *map(str, objects)])
    symbols = set()
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) >= 3 and fields[-2] not in {"U", "u"} and len(fields[-2]) == 1:
            symbols.add(fields[-1].lstrip("_"))
    return symbols


def check_symbols(bin_path, enabled):
    symbols = defined_symbols(bin_path)
    for requirements, c_function, cpp_function in PROBES:
        should_exist = requirements <= enabled
        if (c_function in symbols) != should_exist:
            raise RuntimeError(f"Unexpected C symbol availability: {c_function} ({sorted(enabled)})")
        if cpp_function is None:
            continue
        mangled_prefix = f"ZN7simdutf{len(cpp_function)}{cpp_function}E"
        cpp_exists = any(symbol.startswith(mangled_prefix) for symbol in symbols)
        if cpp_exists != should_exist:
            raise RuntimeError(f"Unexpected upstream C++ symbol availability: {cpp_function} ({sorted(enabled)})")


def check_public_api(bin_path, enabled):
    modulemap = bin_path / "CSimdUTF.build" / "module.modulemap"
    if not modulemap.exists():
        raise RuntimeError(f"Missing generated C module map: {modulemap}")
    compiler_arguments = [
        "swiftc", "-typecheck", "-I", str(bin_path / "Modules"),
        "-I", str(ROOT / "Sources" / "CSimdUTF" / "include"),
        "-Xcc", f"-fmodule-map-file={modulemap}",
    ]
    with tempfile.TemporaryDirectory(prefix="simdutf-api-") as temporary:
        probe = pathlib.Path(temporary) / "Probe.swift"
        probe.write_text("import SimdUTF\nlet _ = SIMDUTF_ERROR_SUCCESS\n")
        # Validate the compiler invocation independently before expecting failures.
        run([*compiler_arguments, str(probe)])
        for requirements, function, _ in PROBES:
            probe.write_text(f"import SimdUTF\nlet _ = {function}\n")
            result = run([*compiler_arguments, str(probe)], check=False)
            should_exist = requirements <= enabled
            if should_exist and result.returncode:
                sys.stderr.write(result.stderr)
                raise RuntimeError(f"Enabled Swift API cannot be imported: {function}")
            if not should_exist:
                if not result.returncode:
                    raise RuntimeError(f"Disabled Swift API remains accessible: {function}")
                if not re.search(rf"cannot find '{re.escape(function)}' in scope", result.stderr):
                    sys.stderr.write(result.stderr)
                    raise RuntimeError(f"Swift API probe failed for an unrelated reason: {function}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", choices=["debug", "release"], default="debug")
    arguments = parser.parse_args()
    configurations = [
        ("defaults", None),
        ("no traits", []),
        *[(feature, [feature]) for feature in sorted(FEATURES)],
        ("UTF8 + ASCII", ["UTF8", "ASCII"]),
        ("All", ["All"]),
    ]
    for name, traits in configurations:
        print(f"Testing {name} ({arguments.configuration})…", flush=True)
        flags = build_arguments(traits, arguments.configuration)
        run(["swift", "test", *flags])
        bin_path = pathlib.Path(run(["swift", "build", *flags, "--show-bin-path"]).stdout.strip())
        enabled = enabled_traits(traits)
        check_symbols(bin_path, enabled)
        check_public_api(bin_path, enabled)
        print(f"  passed tests, symbol checks, and Swift API checks", flush=True)
    print(f"All {len(configurations)} configurations passed.", flush=True)


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as error:
        sys.stderr.write(f"{error}\n")
        sys.exit(1)
