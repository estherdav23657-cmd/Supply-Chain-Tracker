(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-manufacturer-only (err u105))
(define-constant err-product-recalled (err u106))
(define-constant err-role-forbidden (err u107))
(define-constant err-invalid-transition (err u108))
(define-constant err-no-pending-transfer (err u109))
(define-constant err-transfer-expired (err u110))
(define-constant err-not-certifier (err u111))
(define-constant err-invalid-reputation (err u112))
(define-constant err-already-deactivated (err u113))
(define-constant err-not-deactivated (err u114))
(define-constant err-already-resolved (err u115))
(define-constant err-recall-not-found (err u116))

(define-data-var last-product-id uint u0)

(define-map participants
    principal
    {
        name: (string-ascii 50),
        role: (string-ascii 20),
        active: bool,
    }
)

(define-map products
    uint
    {
        name: (string-ascii 50),
        manufacturer: principal,
        owner: principal,
        status: (string-ascii 50),
        timestamp: uint,
    }
)

(define-map product-history
    {
        product-id: uint,
        index: uint,
    }
    {
        owner: principal,
        status: (string-ascii 50),
        timestamp: uint,
    }
)

(define-map product-history-count
    uint
    uint
)

(define-map pending-transfers
    uint
    {
        to: principal,
        expires-at: uint,
    }
)

(define-map valid-transitions
    {
        from: (string-ascii 50),
        to: (string-ascii 50),
    }
    bool
)

(define-map product-certifications
    {
        product-id: uint,
        certifier: principal,
    }
    {
        label: (string-ascii 50),
        issued-at: uint,
    }
)

(define-map product-attributes
    {
        product-id: uint,
        key: (string-ascii 30),
    }
    (string-ascii 100)
)

(define-map product-attribute-count
    uint
    uint
)

(define-map recall-records
    uint
    {
        reason: (string-ascii 100),
        recalled-at: uint,
        resolved: bool,
        resolved-at: uint,
        resolution-notes: (string-ascii 100),
    }
)

(define-map participant-reputation
    principal
    {
        transfers-completed: uint,
        transfers-failed: uint,
        recalls-involved: uint,
    }
)

(define-map deactivation-log
    principal
    {
        deactivated-at: uint,
        reason: (string-ascii 100),
    }
)

(define-map role-permissions
    (string-ascii 20)
    {
        can-mint: bool,
        can-transfer: bool,
        can-update-status: bool,
    }
)

(map-set role-permissions "MANUFACTURER" {
    can-mint: true,
    can-transfer: true,
    can-update-status: true,
})

(map-set role-permissions "DISTRIBUTOR" {
    can-mint: false,
    can-transfer: true,
    can-update-status: true,
})

(map-set role-permissions "RETAILER" {
    can-mint: false,
    can-transfer: false,
    can-update-status: true,
})

(define-public (set-role-permission
        (role (string-ascii 20))
        (can-mint bool)
        (can-transfer bool)
        (can-update-status bool)
    )
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set role-permissions role {
            can-mint: can-mint,
            can-transfer: can-transfer,
            can-update-status: can-update-status,
        }))
    )
)

(define-public (add-participant
        (participant principal)
        (name (string-ascii 50))
        (role (string-ascii 20))
    )
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-none (map-get? participants participant))
            err-already-exists
        )
        (map-set participant-reputation participant {
            transfers-completed: u0,
            transfers-failed: u0,
            recalls-involved: u0,
        })
        (ok (map-set participants participant {
            name: name,
            role: role,
            active: true,
        }))
    )
)

(define-public (deactivate-participant
        (participant principal)
        (reason (string-ascii 100))
    )
    (let ((participant-data (unwrap! (map-get? participants participant) err-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (get active participant-data) err-already-deactivated)

        (map-set participants participant
            (merge participant-data { active: false })
        )
        (map-set deactivation-log participant {
            deactivated-at: burn-block-height,
            reason: reason,
        })
        (ok true)
    )
)

(define-public (reactivate-participant (participant principal))
    (let ((participant-data (unwrap! (map-get? participants participant) err-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (not (get active participant-data)) err-not-deactivated)

        (map-set participants participant
            (merge participant-data { active: true })
        )
        (map-delete deactivation-log participant)
        (ok true)
    )
)

(define-public (set-valid-transition
        (from (string-ascii 50))
        (to (string-ascii 50))
        (is-valid bool)
    )
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set valid-transitions {
            from: from,
            to: to,
        }
            is-valid
        ))
    )
)

(define-public (mint-product (name (string-ascii 50)))
    (let (
            (product-id (+ (var-get last-product-id) u1))
            (sender tx-sender)
            (participant-curr (unwrap! (map-get? participants sender) err-unauthorized))
            (role-cap (unwrap! (map-get? role-permissions (get role participant-curr))
                err-role-forbidden
            ))
        )
        (asserts! (get active participant-curr) err-unauthorized)
        (asserts! (get can-mint role-cap) err-role-forbidden)
        (map-insert products product-id {
            name: name,
            manufacturer: sender,
            owner: sender,
            status: "MANUFACTURED",
            timestamp: burn-block-height,
        })
        (map-set product-history {
            product-id: product-id,
            index: u0,
        } {
            owner: sender,
            status: "MANUFACTURED",
            timestamp: burn-block-height,
        })
        (map-set product-history-count product-id u1)
        (var-set last-product-id product-id)
        (print {
            event: "mint",
            product-id: product-id,
            manufacturer: sender,
        })
        (ok product-id)
    )
)

(define-public (initiate-transfer
        (product-id uint)
        (new-owner principal)
    )
    (let (
            (product (unwrap! (map-get? products product-id) err-not-found))
            (sender tx-sender)
            (sender-participant (unwrap! (map-get? participants sender) err-unauthorized))
            (receiver-participant (unwrap! (map-get? participants new-owner) err-unauthorized))
            (sender-role-cap (unwrap! (map-get? role-permissions (get role sender-participant))
                err-unauthorized
            ))
        )
        (asserts! (is-eq (get owner product) sender) err-unauthorized)
        (asserts! (is-eq (get active sender-participant) true) err-unauthorized)
        (asserts! (is-eq (get active receiver-participant) true) err-unauthorized)
        (asserts! (not (is-eq (get status product) "RECALLED"))
            err-product-recalled
        )
        (asserts! (get can-transfer sender-role-cap) err-role-forbidden)
        (asserts!
            (default-to false
                (map-get? valid-transitions {
                    from: (get status product),
                    to: "TRANSFERRED",
                })
            )
            err-invalid-transition
        )

        (map-set pending-transfers product-id {
            to: new-owner,
            expires-at: (+ burn-block-height u144),
        })

        (print {
            event: "transfer-initiated",
            product-id: product-id,
            from: sender,
            to: new-owner,
            expires-at: (+ burn-block-height u144),
        })
        (ok true)
    )
)

(define-public (accept-transfer (product-id uint))
    (let (
            (product (unwrap! (map-get? products product-id) err-not-found))
            (pending-transfer (unwrap! (map-get? pending-transfers product-id)
                err-no-pending-transfer
            ))
            (receiver tx-sender)
            (receiver-participant (unwrap! (map-get? participants receiver) err-unauthorized))
            (current-history-count (default-to u0 (map-get? product-history-count product-id)))
        )
        (asserts! (is-eq (get to pending-transfer) receiver) err-unauthorized)
        (asserts! (is-eq (get active receiver-participant) true) err-unauthorized)
        (asserts! (< burn-block-height (get expires-at pending-transfer))
            err-transfer-expired
        )
        (asserts! (not (is-eq (get status product) "RECALLED"))
            err-product-recalled
        )

        (map-set products product-id
            (merge product {
                owner: receiver,
                status: "TRANSFERRED",
                timestamp: burn-block-height,
            })
        )

        (map-set product-history {
            product-id: product-id,
            index: current-history-count,
        } {
            owner: receiver,
            status: "TRANSFERRED",
            timestamp: burn-block-height,
        })
        (map-set product-history-count product-id (+ current-history-count u1))

        (map-delete pending-transfers product-id)

        ;; Update reputation for both sender (the previous owner) and receiver
        (let (
                (sender (get owner product))
                (sender-rep (default-to {
                    transfers-completed: u0,
                    transfers-failed: u0,
                    recalls-involved: u0,
                }
                    (map-get? participant-reputation sender)
                ))
                (receiver-rep (default-to {
                    transfers-completed: u0,
                    transfers-failed: u0,
                    recalls-involved: u0,
                }
                    (map-get? participant-reputation receiver)
                ))
            )
            (map-set participant-reputation sender
                (merge sender-rep { transfers-completed: (+ (get transfers-completed sender-rep) u1) })
            )
            (map-set participant-reputation receiver
                (merge receiver-rep { transfers-completed: (+ (get transfers-completed receiver-rep) u1) })
            )
        )

        (print {
            event: "transfer-accepted",
            product-id: product-id,
            to: receiver,
        })
        (ok true)
    )
)

(define-public (cancel-transfer (product-id uint))
    (let (
            (product (unwrap! (map-get? products product-id) err-not-found))
            (sender tx-sender)
        )
        (asserts! (is-eq (get owner product) sender) err-unauthorized)
        (asserts! (is-some (map-get? pending-transfers product-id))
            err-no-pending-transfer
        )

        (map-delete pending-transfers product-id)

        (print {
            event: "transfer-canceled",
            product-id: product-id,
            by: sender,
        })
        (ok true)
    )
)

(define-public (expire-transfer (product-id uint))
    (let (
            (pending-transfer (unwrap! (map-get? pending-transfers product-id)
                err-no-pending-transfer
            ))
            (receiver (get to pending-transfer))
            (receiver-rep (default-to {
                transfers-completed: u0,
                transfers-failed: u0,
                recalls-involved: u0,
            }
                (map-get? participant-reputation receiver)
            ))
        )
        (asserts! (>= burn-block-height (get expires-at pending-transfer))
            err-transfer-expired
        )

        (map-delete pending-transfers product-id)

        ;; Penalize the intended receiver for letting it expire
        (map-set participant-reputation receiver
            (merge receiver-rep { transfers-failed: (+ (get transfers-failed receiver-rep) u1) })
        )

        (print {
            event: "transfer-expired",
            product-id: product-id,
        })
        (ok true)
    )
)

(define-public (set-product-attribute
        (product-id uint)
        (key (string-ascii 30))
        (value (string-ascii 100))
    )
    (let (
            (product (unwrap! (map-get? products product-id) err-not-found))
            (sender tx-sender)
            (current-count (default-to u0 (map-get? product-attribute-count product-id)))
            (is-new-key (is-none (map-get? product-attributes {
                product-id: product-id,
                key: key,
            })))
        )
        (asserts! (is-eq (get owner product) sender) err-unauthorized)

        (map-set product-attributes {
            product-id: product-id,
            key: key,
        }
            value
        )

        (if is-new-key
            (map-set product-attribute-count product-id (+ current-count u1))
            true
        )

        (print {
            event: "attribute-set",
            product-id: product-id,
            key: key,
            value: value,
        })
        (ok true)
    )
)

(define-public (remove-product-attribute
        (product-id uint)
        (key (string-ascii 30))
    )
    (let (
            (product (unwrap! (map-get? products product-id) err-not-found))
            (sender tx-sender)
            (current-count (default-to u0 (map-get? product-attribute-count product-id)))
        )
        (asserts! (is-eq (get owner product) sender) err-unauthorized)
        (asserts!
            (is-some (map-get? product-attributes {
                product-id: product-id,
                key: key,
            }))
            err-not-found
        )

        (map-delete product-attributes {
            product-id: product-id,
            key: key,
        })

        (map-set product-attribute-count product-id (- current-count u1))

        (print {
            event: "attribute-removed",
            product-id: product-id,
            key: key,
        })
        (ok true)
    )
)

(define-public (attest-product
        (product-id uint)
        (label (string-ascii 50))
    )
    (let (
            (product (unwrap! (map-get? products product-id) err-not-found))
            (certifier tx-sender)
            (is-auth-certifier (unwrap! (contract-call? .certifier-registry is-certifier certifier)
                err-not-certifier
            ))
        )
        (asserts! is-auth-certifier err-not-certifier)

        (map-set product-certifications {
            product-id: product-id,
            certifier: certifier,
        } {
            label: label,
            issued-at: burn-block-height,
        })

        (print {
            event: "product-attested",
            product-id: product-id,
            certifier: certifier,
            label: label,
        })
        (ok true)
    )
)

(define-public (revoke-certification (product-id uint))
    (let ((certifier tx-sender))
        (asserts!
            (is-some (map-get? product-certifications {
                product-id: product-id,
                certifier: certifier,
            }))
            err-not-found
        )

        (map-delete product-certifications {
            product-id: product-id,
            certifier: certifier,
        })

        (print {
            event: "certification-revoked",
            product-id: product-id,
            certifier: certifier,
        })
        (ok true)
    )
)

(define-public (update-status
        (product-id uint)
        (new-status (string-ascii 50))
    )
    (let (
            (product (unwrap! (map-get? products product-id) err-not-found))
            (sender tx-sender)
            (participant (unwrap! (map-get? participants sender) err-unauthorized))
            (role-cap (unwrap! (map-get? role-permissions (get role participant))
                err-role-forbidden
            ))
            (current-history-count (default-to u0 (map-get? product-history-count product-id)))
        )
        (asserts! (is-eq (get owner product) sender) err-unauthorized)
        (asserts! (get active participant) err-unauthorized)
        (asserts! (not (is-eq (get status product) "RECALLED"))
            err-product-recalled
        )
        (asserts! (get can-update-status role-cap) err-role-forbidden)

        (map-set products product-id
            (merge product {
                status: new-status,
                timestamp: burn-block-height,
            })
        )

        (map-set product-history {
            product-id: product-id,
            index: current-history-count,
        } {
            owner: sender,
            status: new-status,
            timestamp: burn-block-height,
        })
        (map-set product-history-count product-id (+ current-history-count u1))

        (print {
            event: "status-update",
            product-id: product-id,
            status: new-status,
        })
        (ok true)
    )
)

(define-public (recall-product
        (product-id uint)
        (reason (string-ascii 100))
    )
    (let (
            (product (unwrap! (map-get? products product-id) err-not-found))
            (sender tx-sender)
            (current-history-count (default-to u0 (map-get? product-history-count product-id)))
        )
        (asserts! (is-eq (get manufacturer product) sender) err-manufacturer-only)
        (asserts! (not (is-eq (get status product) "RECALLED"))
            err-product-recalled
        )
        (asserts!
            (default-to false
                (map-get? valid-transitions {
                    from: (get status product),
                    to: "RECALLED",
                })
            )
            err-invalid-transition
        )

        (map-set products product-id
            (merge product {
                status: "RECALLED",
                timestamp: burn-block-height,
            })
        )

        (map-set product-history {
            product-id: product-id,
            index: current-history-count,
        } {
            owner: (get owner product),
            status: "RECALLED",
            timestamp: burn-block-height,
        })
        (map-set product-history-count product-id (+ current-history-count u1))

        ;; Update recall-involved penalty for the manufacturer and current owner
        (let (
                (mfg sender)
                (curr-owner (get owner product))
                (mfg-rep (default-to {
                    transfers-completed: u0,
                    transfers-failed: u0,
                    recalls-involved: u0,
                }
                    (map-get? participant-reputation mfg)
                ))
                (owner-rep (default-to {
                    transfers-completed: u0,
                    transfers-failed: u0,
                    recalls-involved: u0,
                }
                    (map-get? participant-reputation curr-owner)
                ))
            )
            (map-set participant-reputation mfg
                (merge mfg-rep { recalls-involved: (+ (get recalls-involved mfg-rep) u1) })
            )
            (if (not (is-eq mfg curr-owner))
                (map-set participant-reputation curr-owner
                    (merge owner-rep { recalls-involved: (+ (get recalls-involved owner-rep) u1) })
                )
                true ;; Do nothing if the manufacturer still owns it (already penalized)
            )
        )

        (map-set recall-records product-id {
            reason: reason,
            recalled-at: burn-block-height,
            resolved: false,
            resolved-at: u0,
            resolution-notes: "",
        })

        (print {
            event: "recall",
            product-id: product-id,
            manufacturer: sender,
            reason: reason,
        })
        (ok true)
    )
)

(define-public (resolve-recall
        (product-id uint)
        (resolution-notes (string-ascii 100))
    )
    (let (
            (product (unwrap! (map-get? products product-id) err-not-found))
            (sender tx-sender)
            (current-history-count (default-to u0 (map-get? product-history-count product-id)))
            (recall-record (unwrap! (map-get? recall-records product-id) err-recall-not-found))
        )
        (asserts! (is-eq (get manufacturer product) sender) err-manufacturer-only)
        (asserts! (is-eq (get status product) "RECALLED") err-invalid-status)
        (asserts! (not (get resolved recall-record)) err-already-resolved)
        (asserts!
            (default-to false
                (map-get? valid-transitions {
                    from: "RECALLED",
                    to: "MANUFACTURED",
                })
            )
            err-invalid-transition
        )

        (map-set recall-records product-id
            (merge recall-record {
                resolved: true,
                resolved-at: burn-block-height,
                resolution-notes: resolution-notes,
            })
        )

        (map-set products product-id
            (merge product {
                status: "MANUFACTURED",
                timestamp: burn-block-height,
            })
        )

        (map-set product-history {
            product-id: product-id,
            index: current-history-count,
        } {
            owner: (get owner product),
            status: "MANUFACTURED",
            timestamp: burn-block-height,
        })
        (map-set product-history-count product-id (+ current-history-count u1))

        (print {
            event: "recall-resolved",
            product-id: product-id,
            manufacturer: sender,
            resolution-notes: resolution-notes,
        })
        (ok true)
    )
)

(define-read-only (get-product (product-id uint))
    (map-get? products product-id)
)

(define-read-only (get-participant (participant principal))
    (map-get? participants participant)
)

(define-read-only (get-product-history
        (product-id uint)
        (index uint)
    )
    (map-get? product-history {
        product-id: product-id,
        index: index,
    })
)

(define-read-only (get-product-history-count (product-id uint))
    (default-to u0 (map-get? product-history-count product-id))
)

(define-read-only (get-last-product-id)
    (ok (var-get last-product-id))
)

(define-read-only (is-participant-active (participant principal))
    (match (map-get? participants participant)
        participant-data (get active participant-data)
        false
    )
)

(define-read-only (get-role-permissions (role (string-ascii 20)))
    (map-get? role-permissions role)
)

(define-read-only (get-caller-permissions)
    (match (map-get? participants tx-sender)
        participant-data (map-get? role-permissions (get role participant-data))
        none
    )
)

(define-read-only (is-valid-transition
        (from (string-ascii 50))
        (to (string-ascii 50))
    )
    (default-to false
        (map-get? valid-transitions {
            from: from,
            to: to,
        })
    )
)

(define-read-only (get-owner-of-product (product-id uint))
    (match (map-get? products product-id)
        product-data (ok (get owner product-data))
        err-not-found
    )
)

(define-read-only (get-product-manufacturer (product-id uint))
    (match (map-get? products product-id)
        product-data (ok (get manufacturer product-data))
        err-not-found
    )
)

(define-read-only (get-product-status (product-id uint))
    (match (map-get? products product-id)
        product-data (ok (get status product-data))
        err-not-found
    )
)

(define-read-only (get-reputation (participant principal))
    (default-to {
        transfers-completed: u0,
        transfers-failed: u0,
        recalls-involved: u0,
    }
        (map-get? participant-reputation participant)
    )
)

(define-public (slash-reputation
        (participant principal)
        (failed-penalty uint)
        (recall-penalty uint)
    )
    (let ((rep (default-to {
            transfers-completed: u0,
            transfers-failed: u0,
            recalls-involved: u0,
        }
            (map-get? participant-reputation participant)
        )))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set participant-reputation participant {
            transfers-completed: (get transfers-completed rep),
            transfers-failed: (+ (get transfers-failed rep) failed-penalty),
            recalls-involved: (+ (get recalls-involved rep) recall-penalty),
        }))
    )
)

(define-read-only (get-pending-transfer (product-id uint))
    (map-get? pending-transfers product-id)
)

(define-read-only (get-certification
        (product-id uint)
        (certifier principal)
    )
    (map-get? product-certifications {
        product-id: product-id,
        certifier: certifier,
    })
)

(define-read-only (is-certified
        (product-id uint)
        (certifier principal)
    )
    (is-some (map-get? product-certifications {
        product-id: product-id,
        certifier: certifier,
    }))
)

(define-read-only (get-product-attribute
        (product-id uint)
        (key (string-ascii 30))
    )
    (map-get? product-attributes {
        product-id: product-id,
        key: key,
    })
)

(define-read-only (get-product-attribute-count (product-id uint))
    (default-to u0 (map-get? product-attribute-count product-id))
)

(define-read-only (get-deactivation-log (participant principal))
    (map-get? deactivation-log participant)
)

(define-read-only (get-recall-record (product-id uint))
    (map-get? recall-records product-id)
)

(define-read-only (is-recall-resolved (product-id uint))
    (match (map-get? recall-records product-id)
        record (get resolved record)
        false
    )
)

(define-read-only (was-participant-ever-active (participant principal))
    (is-some (map-get? participants participant))
)

(define-read-only (get-products-page (start-id uint))
    (map get-product
        (list
            start-id
            (+ start-id u1)
            (+ start-id u2)
            (+ start-id u3)
            (+ start-id u4)
            (+ start-id u5)
            (+ start-id u6)
            (+ start-id u7)
            (+ start-id u8)
            (+ start-id u9)
        )
    )
)

(define-private (get-product-history-tuple (key { product-id: uint, index: uint }))
    (get-product-history (get product-id key) (get index key))
)

(define-read-only (get-product-history-page (product-id uint) (start-index uint))
    (map get-product-history-tuple
        (list
            { product-id: product-id, index: start-index }
            { product-id: product-id, index: (+ start-index u1) }
            { product-id: product-id, index: (+ start-index u2) }
            { product-id: product-id, index: (+ start-index u3) }
            { product-id: product-id, index: (+ start-index u4) }
            { product-id: product-id, index: (+ start-index u5) }
            { product-id: product-id, index: (+ start-index u6) }
            { product-id: product-id, index: (+ start-index u7) }
            { product-id: product-id, index: (+ start-index u8) }
            { product-id: product-id, index: (+ start-index u9) }
        )
    )
)
