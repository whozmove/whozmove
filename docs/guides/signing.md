# Signing your own builds

Whozmove's releases are signed with its developer's Developer ID, so the permissions you give it (Accessibility,
Automation, Full Disk Access) are kept for that signature, through every update. A build you make yourself with
`./build.sh` is signed ad hoc unless you set up a Developer ID of your own, as below: then each build you or Deploy
makes here is signed with it, and keeps the permissions you gave the last one.

This needs a membership of Apple's Developer Program, as the account holder.

## Setting it up, once

1. **Apple's intermediate certificate.** At [apple.com/certificateauthority](https://www.apple.com/certificateauthority/)
   download Developer ID - G2, and double-click it. (Xcode puts it in for you; without Xcode, it's this.)
2. **A keychain and a request.** In Terminal, in your checkout: `tools/signing.sh new`. It makes Whozmove's signing
   keychain, asking you to choose a password for it: one you use for nothing else, kept where you keep passwords. Then
   it makes the request for your certificate, whose private key is made in that keychain and never leaves it. Your
   default keychain stays as it is; the signing keychain goes last on the list of keychains macOS searches, as
   codesign finds a certificate only there. The request goes on your Desktop.
3. **The certificate.** At
   [developer.apple.com/account/resources/certificates/add](https://developer.apple.com/account/resources/certificates/add),
   pick Developer ID ▸ Developer ID Application (and G2 Sub-CA if it asks), upload the request, and download the
   certificate.
4. **Put it in.** `tools/signing.sh add <the certificate you downloaded>`. It says when builds here are ready to be
   signed.

## Each build

`./build.sh`, or Deploy in Whozmove, says before signing that macOS will ask for your signing keychain's password a
few times, each time codesign uses your key as it signs Betterleaks, which Keys looks with, and Whozmove. Give it each
time, and press **Allow**. The keychain is locked again as soon as signing ends, so it's open only for those boxes.
The key lets Apple's own tools ask for it, each asking every time; you allow only the boxes that follow a build of
yours.

- **Never press Always Allow.** It would let anything on this Mac sign as you while the keychain is open, and an app
  signed with your key gets the permissions you gave your builds.
- **A box you didn't expect is a Deny.** A build starts with no press of yours in two ways: a Deploy you let a
  session ask for (Let It Deploy), and a Deploy you pressed while an agent worked, kept until it stopped. A box that
  follows neither, nor your own Deploy or `./build.sh`, is something else asking to sign with your key.
- **Deny, or cancel, and nothing goes in:** the app you have keeps running. Deploy again to try again.
- **An agent's build is never signed with your key, and never goes in by itself:** it's ad hoc, and goes in only
  through Deploy (or your own `./build.sh`), signed by you.

A checkout from before signing your own builds was added builds ad hoc, as an agent's does, so Deploy from checkouts
that have it.

## When something goes wrong

- **The certificate is in, but builds still stop.** Most often Apple's Developer ID - G2 certificate is missing (step
  1): put it in, and run `tools/signing.sh add` again.
- **Back to ad hoc builds.** Take `~/Library/Keychains/whozmove-signing.keychain-db` out: builds are ad hoc again.
- **A forgotten password.** There's no way back into the keychain: take
  `~/Library/Keychains/whozmove-signing.keychain-db` out, and set it up again from step 2 with a new certificate (Apple
  lets you have five Developer ID Application certificates).
- **An expired certificate.** A build stops before it starts, saying the keychain holds no certificate that works:
  make a new request (step 2, after taking the old keychain out) and certificate.
- **A key that may have got out.** Only Apple can revoke a Developer ID certificate, by email to
  product-security@apple.com, and every app signed with it then stops opening. Make a new one first.
