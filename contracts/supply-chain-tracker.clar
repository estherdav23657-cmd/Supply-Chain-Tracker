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
    { to: principal, expires-at: uint }
)

(define-map valid-transitions
    {
        from: (string-ascii 50),
        to: (string-ascii 50),
    }
    bool
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
        (ok (map-set participants participant {
            name: name,
            role: role,
            active: true,
        }))
    )
)

(define-public (remove-participant (participant principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-some (map-get? participants participant)) err-not-found)
        (ok (map-delete participants participant))
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
            (role-cap (unwrap! (map-get? role-permissions (get role participant-curr)) err-role-forbidden))
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
            (sender-role-cap (unwrap! (map-get? role-permissions (get role sender-participant)) err-unauthorized))
        )
        (asserts! (is-eq (get owner product) sender) err-unauthorized)
        (asserts! (is-eq (get active sender-participant) true) err-unauthorized)
        (asserts! (is-eq (get active receiver-participant) true) err-unauthorized)
        (asserts! (not (is-eq (get status product) "RECALLED")) err-product-recalled)
        (asserts! (get can-transfer sender-role-cap) err-role-forbidden)
        (asserts! (default-to false (map-get? valid-transitions { from: (get status product), to: "TRANSFERRED" })) err-invalid-transition)

        (map-set pending-transfers product-id {
            to: new-owner,
            expires-at: (+ burn-block-height u144)
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
            (pending-transfer (unwrap! (map-get? pending-transfers product-id) err-no-pending-transfer))
            (receiver tx-sender)
            (receiver-participant (unwrap! (map-get? participants receiver) err-unauthorized))
            (current-history-count (default-to u0 (map-get? product-history-count product-id)))
        )
        (asserts! (is-eq (get to pending-transfer) receiver) err-unauthorized)
        (asserts! (is-eq (get active receiver-participant) true) err-unauthorized)
        (asserts! (< burn-block-height (get expires-at pending-transfer)) err-transfer-expired)
        (asserts! (not (is-eq (get status product) "RECALLED")) err-product-recalled)

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
        (asserts! (is-some (map-get? pending-transfers product-id)) err-no-pending-transfer)

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
            (pending-transfer (unwrap! (map-get? pending-transfers product-id) err-no-pending-transfer))
        )
        (asserts! (>= burn-block-height (get expires-at pending-transfer)) err-transfer-expired)

        (map-delete pending-transfers product-id)

        (print {
            event: "transfer-expired",
            product-id: product-id,
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
            (role-cap (unwrap! (map-get? role-permissions (get role participant)) err-role-forbidden))
            (current-history-count (default-to u0 (map-get? product-history-count product-id)))
        )
        (asserts! (is-eq (get owner product) sender) err-unauthorized)
        (asserts! (get active participant) err-unauthorized)
        (asserts! (not (is-eq (get status product) "RECALLED")) err-product-recalled)
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

(define-public (recall-product (product-id uint))
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

        (print {
            event: "recall",
            product-id: product-id,
            manufacturer: sender,
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

(define-read-only (get-pending-transfer (product-id uint))
    (map-get? pending-transfers product-id)
)
