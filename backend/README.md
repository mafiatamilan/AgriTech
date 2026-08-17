# Smart Farming Backend

FastAPI backend for a smart farming platform that helps farmers monitor irrigation, track crop health/yield via AI agents, and match surplus/perishable crops with nearby buyers.

## Tech Stack

- **Framework**: FastAPI (async) + Uvicorn
- **Database & Auth**: Supabase (Postgres + Auth)
- **Storage**: Supabase Storage (crop images)
- **Background Jobs**: APScheduler
- **Validation**: Pydantic v2

## Setup

### 1. Install dependencies

```bash
cd backend
pip install -r requirements.txt
```

### 2. Configure environment

```bash
cp .env.example .env
# Edit .env with your Supabase credentials
```

Required env vars:
- `SUPABASE_URL` — your Supabase project URL
- `SUPABASE_ANON_KEY` — anonymous/public key
- `SUPABASE_SERVICE_ROLE_KEY` — service role key (for admin operations)
- `SUPABASE_JWT_SECRET` — JWT secret from Supabase auth settings
- `DATABASE_URL` — direct Postgres connection string

### 3. Run database migrations

Run the SQL in `migrations/001_initial_schema.sql` against your Supabase Postgres database (via the SQL Editor in Supabase dashboard or `psql`).

### 4. Start the server

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

The APScheduler starts automatically with the app.

### 5. Run tests

```bash
pytest tests/ -v
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | /auth/signup | Register new farmer |
| POST | /auth/login | Login |
| GET | /auth/me | Current farmer profile |
| GET | /farms | List farms |
| POST | /farms | Create farm |
| GET | /farms/{id} | Get farm |
| PATCH | /farms/{id} | Update farm |
| GET | /motor/status | Irrigation status |
| POST | /motor/stop-current | Stop running irrigation |
| POST | /motor/cancel-next | Cancel next scheduled |
| POST | /motor/on | Manual motor on |
| POST | /market/crop-match | Match crop with buyers |
| GET | /market/requests | List demand requests |
| PATCH | /market/{id}/extend-shelf-life | Extend shelf life |
| POST | /upload/crop-image | Upload crop image |
| GET | /upload/{id}/status | Analysis status |
| GET | /recommendations | Farm recommendations |
| GET | /settings | Get settings |
| PATCH | /settings | Update settings |
| GET | /account | Account info |
| PATCH | /account | Update account |
| GET | /notifications | List notifications |
| PATCH | /notifications/{id}/read | Mark as read |

## Project Structure

```
backend/
├── app/
│   ├── main.py              # FastAPI app + router wiring
│   ├── core/                 # Config, security, dependencies
│   ├── db/                   # Supabase client
│   ├── models/               # Pydantic schemas
│   ├── routers/              # API route handlers
│   ├── agents/               # AI agent stubs (swappable)
│   ├── services/             # Business logic
│   └── workers/              # APScheduler background jobs
├── migrations/               # SQL migration files
├── tests/                    # Pytest tests
├── requirements.txt
└── .env.example
```
