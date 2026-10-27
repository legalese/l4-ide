# Camunda DMN check: pin the JDK, and clear the class cache when you change it

`run.sh` drives an emitted DMN file through Camunda 8 (`io.camunda:zeebe-dmn`), as the header of `run.sh` explains.
This note was moved here from `CLAUDE.md` §3.1 on 2026-10-27.
The line numbers below were checked against `run.sh` on that date.

## The JDK it picks is the newest one it finds, and CI runs 21

`run.sh` ignores the bare `java` on `PATH`.
It exports `JAVA_HOME` from `CAMUNDA_CHECK_JAVA_HOME` (`run.sh:64-66`), and when that is unset it takes the first usable entry of a candidate list (`run.sh:54-63`).
The first entry is `/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home`, deliberately "the newest JDK we can find" (the comment at `run.sh:51-53`; 21 is the floor, because zeebe-dmn is compiled to class file 65).
On a machine with Homebrew's plain `openjdk` that is whatever release Homebrew currently ships (26.0.1 on 2026-10-27).
CI runs 21: the `DMN Engine Checks` job in `.github/workflows/pr-checks.yml` sets `CAMUNDA_CHECK_JAVA_HOME: ${{ env.JAVA_HOME_21_X64 }}`.
So pin `CAMUNDA_CHECK_JAVA_HOME` to a JDK 21 if you want your result to mean what CI's means.

## The compiled-class cache is keyed on the source, not on the JDK

`run.sh:103` recompiles `CamundaDmnCheck.java` only when the class is missing or the source is newer.
It does not look at which JDK compiled the class, so a class built by an earlier run under a different JDK is reused.
The two directions fail differently:

- **Loud.** A class compiled on JDK 26 (class file version 70) and then run on JDK 21 dies with `UnsupportedClassVersionError: CamundaDmnCheck …` before it reaches any DMN.
  That reads as a broken harness rather than a stale cache, because the class named is the harness's own (`run.sh:84-95`).
- **Silent.** A class compiled on 21 and run on 26 loads without complaint, and a class compiled on 26 and run on 26 does too.
  Either is a local green on a different JVM, or on different bytecode, from CI's, and nothing says so.

Do not trust which `java` you invoked.
Read the class-file major version, and reset the cache when you change JDK:

```
CAMUNDA_WORK="${CAMUNDA_CHECK_WORKDIR:-${TMPDIR:-/tmp}/l4-camunda-dmn-check}"   # run.sh:73
od -An -tu1 -N8 "$CAMUNDA_WORK/classes/CamundaDmnCheck.class"                   # the last number: 65 is Java 21
rm -rf "$CAMUNDA_WORK/classes"                                                   # the reset
```

## The fix that is deliberately not applied

The `kie-dmn-check` leg is immune because it compiles with `--release 11` (`etc/kie-dmn-check/run.sh:81`).
`--release 21` on the Camunda leg would fix it the same way, and 21 is already this script's floor.
It is not applied because it changes what every CI run of this checker compiles, which is not a corpus or exporter branch's call (`run.sh:97-102`).
