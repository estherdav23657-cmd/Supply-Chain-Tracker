(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-manufacturer-only (err u105))
(define-constant err-product-recalled (err u106))

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

(define-public (mint-product (name (string-ascii 50)))
    (let (
            (product-id (+ (var-get last-product-id) u1))
            (sender tx-sender)
            (participant-curr (unwrap! (map-get? participants sender) err-unauthorized))
        )
        (asserts! (is-eq (get active participant-curr) true) err-unauthorized)
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

(define-public (transfer-product
        (product-id uint)
        (new-owner principal)
    )
    (let (
            (product (unwrap! (map-get? products product-id) err-not-found))
            (sender tx-sender)
            (sender-participant (unwrap! (map-get? participants sender) err-unauthorized))
            (receiver-participant (unwrap! (map-get? participants new-owner) err-unauthorized))
            (current-history-count (default-to u0 (map-get? product-history-count product-id)))
        )
        (asserts! (is-eq (get owner product) sender) err-unauthorized)
        (asserts! (is-eq (get active sender-participant) true) err-unauthorized)
        (asserts! (is-eq (get active receiver-participant) true) err-unauthorized)
        (asserts! (not (is-eq (get status product) "RECALLED")) err-product-recalled)

        (map-set products product-id
            (merge product {
                owner: new-owner,
                status: "TRANSFERRED",
                timestamp: stacks-block-height,
            })
        )

        (map-set product-history {
            product-id: product-id,
            index: current-history-count,
        } {
            owner: new-owner,
            status: "TRANSFERRED",
            timestamp: burn-block-height,
        })
        (map-set product-history-count product-id (+ current-history-count u1))

        (print {
            event: "transfer",
            product-id: product-id,
            from: sender,
            to: new-owner,
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
            (current-history-count (default-to u0 (map-get? product-history-count product-id)))
        )
        (asserts! (is-eq (get owner product) sender) err-unauthorized)
        (asserts! (is-eq (get active participant) true) err-unauthorized)
        (asserts! (not (is-eq (get status product) "RECALLED")) err-product-recalled)

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
        (asserts! (not (is-eq (get status product) "RECALLED")) err-product-recalled)

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
