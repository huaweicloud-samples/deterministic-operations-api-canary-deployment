/** 稳定版本业务函数：返回当前发布环境标识 */
exports.handler = async (event, context) => ({
  statusCode: 200,
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ message: "Hello from PROD!", env: "prod", timestamp: new Date().toISOString() }),
});
