# Saffire Pro 24 on Windows 11 — legacy driver fix (no test signing)

> **AI-generated project.** The scripts and this document were produced with an AI
> assistant (OpenCode / DeepSeek) from hands-on experiments on real hardware, then
> reviewed and validated by the machine's owner. Treat it as a documented workaround,
> not as vendor-supported software.

Restores Focusrite **Saffire Pro 24** (FireWire) on Windows 11 **24H2 / 25H2** after the
April 2026 **Windows Driver Policy** change — *without* enabling test signing and
*without* re-signing drivers.

## Background

Windows used to trust kernel drivers signed through the legacy *cross-signed* program.
With the April 2026 servicing update, Microsoft removed that trust for Windows 11
24H2/25H2/26H1 and Windows Server 2025. The restriction is implemented as a Code
Integrity policy:

| Policy ID | Meaning |
|---|---|
| `{784C4414-79F4-4C32-A6A5-F0FB42A51D0D}` | “Microsoft Windows Cross Certificates for Code Integrity Exceptions **Audit** Policy” |
| `{8F9CB695-5D48-48D6-A329-7202B44607E3}` | “Microsoft Windows Cross Certificates for Code Integrity Exceptions **Policy**” (enforcing) |

The enforcing policy blocks the last Saffire driver — **4.3.0.41017** (2015, signed by
`TC Applied Technologies` / SHA-1) — with Code Integrity events **3077**.

Microsoft documents how to turn the policy off (see *“How do I turn off the Windows
Driver Policy?”* in Microsoft’s support article “The Windows Driver Policy”). This
project automates that, because the documented `CiTool` command is rejected with
`0x80070005` on some builds, in which case the policy file has to be removed from the
EFI System Partition manually.

Once the policy is gone, Windows falls back to trusting the old cross-signed
certificates and the **original** Focusrite driver loads normally.

## What you get

- `testsigning` stays **off** → Secure Boot can stay **on**, kernel anti-cheat works,
  no “Test Mode” watermark.
- **No driver re-signing**, no self-made certificates: the vendor driver is used as is.
- Works for other legacy cross-signed drivers too (M-Audio, Line 6, X-Rite, …) — the
  scripts are generic.

## Requirements

- Windows 11 24H2 / 25H2 (build 26100+) with the April 2026 update or later.
- The original Focusrite driver package. **It is not included here** (copyright).
  Get it from Focusrite’s download page for the Saffire range
  (`Saffire MixControl 3.7`, driver 4.3.0.41017) and copy these files into `drivers\`:
  `Saffire.inf`, `Saffire.sys`, `SaffireAudio.sys`, `SaffireMidi.sys`, `Saffire.cat`.
  They are also present in `C:\Program Files\Focusrite\Saffire MixControl\` after
  installing MixControl.
- Administrator rights.

## Quick start

```powershell
# 1. put the driver files into .\drivers\  (see above)

# 2. remove the blocking policy
powershell -ExecutionPolicy Bypass -File .\fix-policy.ps1

# 3. install the vendor driver
powershell -ExecutionPolicy Bypass -File .\install.ps1

# 4. reboot
```

Verify after reboot:

```powershell
powershell -ExecutionPolicy Bypass -File .\verify.ps1
```

Expect: services `Saffire`, `SaffireAudio`, `SaffireMidi` = Running, all Saffire device
nodes `OK`, and only **3076** (audit) events in
`Applications and Services Logs → Microsoft → Windows → CodeIntegrity → Operational`.

## Rollback

The policy file is backed up to `.\backup\` before removal. To restore protection:

```powershell
# enable Secure Boot off if it is on, then:
mountvol S: /s
copy .\backup\esp_{8F9CB695-*.CIP} "S:\EFI\Microsoft\Boot\CiPolicies\Active\{8F9CB695-5D48-48D6-A329-7202B44607E3}.cip"
mountvol S: /d
# reboot
```

A Windows cumulative update may also restore the policy by itself.

## Tested on

- Windows 11 Pro 25H2, build 26200.9974, x64
- Gigabyte Z590 AORUS MASTER, Intel i9-10850K
- VIA VT6315N OHCI FireWire controller (`PCI\VEN_1106&DEV_3403`)
- Saffire Pro 24 (`1394\FOCUSRITE&SAFFIRE_PRO_24\…`), MixControl 3.7 / 3.8b1
- Driver package 4.3.0.41017 (`Saffire.inf`)

## ⚠️ Security warning

Removing this policy re-enables trust for the **entire** deprecated cross-signed
program, including old drivers with known vulnerabilities. Microsoft removed that trust
on purpose. Only do this if you actually need the hardware, keep the OS otherwise
updated, and restore the policy if you stop using the device.

## Known caveats

- Running a Focusrite MixControl installer removes the existing driver package (and in
  silent mode does not put it back). Re-run `install.ps1` afterwards.
- Major Windows updates can re-add the policy → re-run `fix-policy.ps1` and reboot.
- Events **3076** for these drivers are expected (audit mode), **3077** means the policy
  is active again.

## Test signing fallback

If a future build refuses to load the driver even with the policy removed, the
alternative is test signing (`bcdedit /set testsigning on`) plus locally re-signing the
driver with a self-signed certificate. That disables Secure Boot trust and breaks
kernel anti-cheat, so it is a last resort and not implemented here.

## License

MIT — see `LICENSE`. No vendor binaries are distributed.

---

## Кратко по-русски

Скрипты чинят Saffire Pro 24 на Windows 11 24H2/25H2 **без тестового режима**: убирают
политику Microsoft `{8F9CB695-…}` (апрель 2026), из-за которой блокируется последний
драйвер Focusrite 4.3.0.41017, и ставят оригинальный драйвер. Драйверы в репозиторий
не входят — положите их в `drivers\` из установщика Focusrite.

Проект сгенерирован ИИ и проверен на реальном железе; используйте на свой риск.
