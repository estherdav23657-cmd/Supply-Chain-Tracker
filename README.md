# 📦 Supply Chain Tracker MVP

A minimal, Clarity-based smart contract for tracking product provenance on the Stacks blockchain. ⛓️

## 🚀 Features

- **Participant Registry**: 👤 Add authorized manufacturers and logistics partners.
- **Product Minting**: 🏭 Manufacturers can mint new products with a unique ID.
- **Provenance Tracking**: 🚚 Transfer ownership and update status (e.g., "In Transit", "Delivered").
- **Authenticity**: ✅ Only registered manufacturers can mint.
- **Full History**: 📜 Events emit every step of the way for off-chain indexing.

## 🛠️ Usage

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed.

### Testing

Run the automated checks and tests:

```bash
clarinet check
clarinet test
```

### Console Interaction

Open the Clarinet console to interact with the contract:

```bash
clarinet console
```

**Example 1: Mint a Product**

```clarity
(contract-call? .supply-chain-tracker mint-product "SuperWidget")
```

**Example 2: Transfer Product**

```clarity
;; Transfer product 1 to a new owner
(contract-call? .supply-chain-tracker transfer-product u1 'ST1SJ3DTE5DN7X54YDH5D64R3BCB6A2AG2ZQ8YPD5)
```

## 📄 Contract Description

The `supply-chain-tracker` contract manages the lifecycle of products. It stores participant details and product history on-chain.

- **Maps**:
  - `participants`: Stores authorized entities.
  - `products`: Current state of each product.
  - `product-history`: Historical records of ownership and status changes.

- **Functions**:
  - `add-participant`: Admin only.
  - `mint-product`: Registered manufacturers only.
  - `transfer-product`: Current owner only.
  - `update-status`: Current owner only.
