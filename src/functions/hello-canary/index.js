/** 候选版本业务函数：验证金丝雀时返回候选标识 */
exports.handler = async (event, context) => ({
  statusCode: 200,
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ message: "Hello from CANARY!", env: "onepod", timestamp: new Date().toISOString() }),
});
