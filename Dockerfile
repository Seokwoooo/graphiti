# 베이스 이미지: 가벼운 파이썬 런타임
FROM python:3.12-slim

########################################
# 1. 기본 OS 패키지 설치 (root 단계)
#    - curl: uv 설치 스크립트 다운로드
#    - build-essential: uv sync 중 빌드 필요한 패키지 대비
#    - ca-certificates: TLS 연결(neo4j+s 등) 안정화
########################################
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl build-essential ca-certificates && \
    rm -rf /var/lib/apt/lists/*

########################################
# 2. uv 설치 (root로)
#    uv 설치 스크립트가 /root/.local/bin/uv 에 바이너리 생성
########################################
RUN curl -fsSL https://astral.sh/uv/install.sh | sh

# uv가 설치된 경로를 우선 PATH에 추가
ENV PATH="/root/.local/bin:${PATH}"

########################################
# 3. uv 바이너리를 전역 실행 가능하게 복사
#    - /usr/local/bin/uv 로 복사해서 모든 유저가 실행 가능(755)
#    - 이렇게 해두면 나중에 일반 유저(app)도 uv 호출 가능
########################################
RUN install -m 755 /root/.local/bin/uv /usr/local/bin/uv

# 안전하게 PATH에 /usr/local/bin도 확실히 포함
ENV PATH="/usr/local/bin:${PATH}"

########################################
# 4. 비루트 유저(app) 생성 (아직 USER 전환은 안 함)
########################################
RUN useradd -m app

########################################
# 5. 애플리케이션 코드 복사 (root로 복사 후 소유권 변경)
########################################
WORKDIR /app
COPY . /app

# 전체 소유권을 app 유저에게 넘김
RUN chown -R app:app /app

########################################
# 6. 런타임용 ENV 기본값 세팅
#    민감값(OPENAI_API_KEY, NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD 등)은
#    절대 여기 넣지 말고 Render 대시보드 env vars에서 넣을 것.
########################################
ENV PORT=8000
ENV DATABASE_TYPE=neo4j
ENV MODEL_NAME=gpt-4o-mini
ENV SMALL_MODEL_NAME=gpt-4o-mini
ENV GRAPHITI_TELEMETRY_ENABLED=false
ENV SEMAPHORE_LIMIT=10

########################################
# 7. 이제부터는 app 유저로 동작
#    여기서부터 생성되는 가상환경(.venv)도 app 소유라
#    권한 문제가 안 생김
########################################
USER app

########################################
# 8. 의존성 설치 (app 유저로 uv sync 실행)
#    mcp_server/ 디렉토리에 pyproject.toml / uv.lock 이 있다고 가정.
#    이 단계에서 /app/mcp_server/.venv 이 app 권한으로 생성됨.
########################################
RUN uv sync --directory /app/mcp_server

########################################
# 9. 컨테이너가 노출하는 포트
########################################
EXPOSE 8000

########################################
# 10. 컨테이너 시작 커맨드
#
#    graphiti_mcp_server.py:
#      - Graphiti MCP 서버 엔트리포인트
#      - Neo4j + OpenAI 기반으로 "대화 기억" 저장/검색 지원
#
#    --transport sse:
#      - /sse 엔드포인트를 연다
#      - Claude Code에서 type:"sse", url:".../sse" 로 붙을 때 이걸 사용
#
#    --host 0.0.0.0 / --port $PORT:
#      - Render가 주입하는 PORT에서 외부로 열기
#
#    --model / --group-id:
#      - 내부 임베딩/요약 모델 이름
#      - 저장되는 메모리 그룹 네임스페이스(apa)
#
#    sh -c 허용 이유:
#      - $PORT 환경변수 치환
#      - uv run 명령을 쉘 경유로 실행
########################################
CMD ["sh", "-c", "uv run --directory /app/mcp_server graphiti_mcp_server.py --transport sse --host 0.0.0.0 --port $PORT --model gpt-4o-mini --group-id apa"]
