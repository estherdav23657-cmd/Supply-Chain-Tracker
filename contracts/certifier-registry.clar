;; Certifier Registry
;; Manages a whitelist of authorized third-party certifiers (e.g., ISO, QA labs)
;; that can attest to the quality/state of a supply chain product.

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))

(define-map certifiers
    principal
    {
        name: (string-ascii 50),
        specialization: (string-ascii 50),
        active: bool,
    }
)

(define-public (add-certifier 
        (certifier principal)
        (name (string-ascii 50))
        (specialization (string-ascii 50))
    )
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-none (map-get? certifiers certifier)) err-already-exists)
        (ok (map-set certifiers certifier {
            name: name,
            specialization: specialization,
            active: true
        }))
    )
)

(define-public (remove-certifier (certifier principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-some (map-get? certifiers certifier)) err-not-found)
        (ok (map-delete certifiers certifier))
    )
)

(define-read-only (is-certifier (certifier principal))
    (ok (match (map-get? certifiers certifier)
        certifier-data (get active certifier-data)
        false
    ))
)

(define-read-only (get-certifier-info (certifier principal))
    (map-get? certifiers certifier)
)
