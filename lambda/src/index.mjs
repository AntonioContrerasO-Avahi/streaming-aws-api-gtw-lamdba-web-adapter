/**
 * Streaming Token Response - AWS Lambda Handler
 * Runtime: nodejs22.x
 *
 * This handler uses awslambda.streamifyResponse() to stream tokens
 * back to the client via API Gateway REST (RESPONSE_STREAM mode).
 *
 * Compatible with: aws provider >= 6.x (uses response_streaming_invoke_arn)
 */

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Simulate an LLM / token source that yields chunks with a delay.
 * Replace this with an actual Bedrock / OpenAI / etc. call in production.
 */
async function* generateTokens(prompt) {
  const words = `You asked: "${prompt}". Here is a streaming response from the Lambda function. Each word arrives as a separate token so you can see the streaming in action. In production you would replace this generator with a real LLM call, for example using the AWS Bedrock Converse stream API or the OpenAI streaming completions endpoint.`.split(
    " "
  );

  for (const word of words) {
    yield word + " ";
    // Simulate token latency (50 ms per token)
    await new Promise((r) => setTimeout(r, 50));
  }
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

export const handler = awslambda.streamifyResponse(
  /**
   * @param {import('aws-lambda').APIGatewayProxyEvent} event
   * @param {import('aws-lambda').ResponseStream} responseStream
   * @param {import('aws-lambda').Context} context
   */
  async (event, responseStream, _context) => {
    // ── 1. Parse the incoming request ────────────────────────────────────
    let prompt = "Hello, world!";
    try {
      if (event.body) {
        const body =
          typeof event.body === "string"
            ? JSON.parse(event.body)
            : event.body;
        if (body.prompt) prompt = body.prompt;
      }
    } catch {
      // fall back to default prompt
    }

    // ── 2. Send HTTP metadata (status + headers) FIRST ──────────────────
    //    API Gateway requires this before any body bytes.
    const metadata = {
      statusCode: 200,
      headers: {
        "Content-Type": "text/event-stream; charset=utf-8",
        "Cache-Control": "no-cache",
        "X-Accel-Buffering": "no",          // tells nginx / CloudFront not to buffer
        "Access-Control-Allow-Origin": "*",
      },
    };

    responseStream = awslambda.HttpResponseStream.from(
      responseStream,
      metadata
    );

    // ── 3. Stream tokens ──────────────────────────────────────────────────
    try {
      for await (const token of generateTokens(prompt)) {
        // SSE format: "data: <payload>\n\n"
        responseStream.write(`data: ${JSON.stringify({ token })}\n\n`);
      }

      // Signal end-of-stream to the client
      responseStream.write(`data: ${JSON.stringify({ done: true })}\n\n`);
    } catch (err) {
      // Stream an error event instead of crashing silently
      responseStream.write(
        `data: ${JSON.stringify({ error: err.message })}\n\n`
      );
    } finally {
      // IMPORTANT: always end the stream or API Gateway will hang
      responseStream.end();
    }
  }
);
